# Some considerations:
#
#   - Having never written Ruby before, there may be some strange idioms in the below code.
#
#   - Per the specification, the load_config API has been implemented as a function.
#     Unfortunately, to track the current config section and ensure overridden settings
#     take priority, we have to maintain some global state during the parsing. To better
#     encapsulate this state, it might make more sense to implement load_config as a class
#     method.
#
#   - To minimize memory usage, the config file is read line-by-line rather than loading it
#     entirely into memory at once.
#
#   - The config object returned from load_config is implemented as an OpenStruct, which
#     itself is backed by a Hash. Thus, all lookup queries will have a time complexity of
#     O(1) amortized. As such, there wouldn't be any real advantage to "caching" values for
#     common queries because it would effectively be the same thing.
#
#   - Section configs are each backed by a subclass of Hash to allow for property-like value
#     lookups. If using Ruby 2.0, it might be slightly safer to do a module-scoped monkey
#     patch using refinements.
#
#   - This is intended to be a fairly robust solution, so most edge cases should be handled
#     reasonably well.
#
#   - Some basic unit tests for load_config can be found in test_config.rb.
#

require 'ostruct'
require 'set'

module Config

  COMMENT_DELIM = ';'
  LIST_DELIM = ','
  OVERRIDE_START_DELIM = '<'
  OVERRIDE_END_DELIM = '>'
  VALUE_ASSIGNMENT = '='
  BOOLEANS = %w(0 1 true false yes no)

  # Matches [foo]
  SECTION_REGEX = /^\[[^\]\r\n]+\](?:\r?\n(?:[^\[\r\n].*)?)*/

  # Matches "foo"
  STRING_REGEX = /['"][^'"]*['"]/

  # Matches a string for truthiness
  BOOLEAN_TRUE_REGEX = /^(true|yes|1)$/i

  $_current_section = nil
  $_overridden = nil


  # Loads the config file at the given path into an OpenStruct. A list of overrides can be
  # specified, either as strings or symbols, in which values with these overrides will take
  # priority.
  def load_config(file_path, overrides=[])

    if file_path.nil? or not File.exist?(file_path)
      raise 'Invalid file path: ' << file_path
    end

    config_hash = {}

    # Ensure globals are reset
    $_current_section = nil
    $_overridden = Set.new

    # Normalize overrides to strings -- symbols would be faster, but we're comparing them
    # with strings from the file in the end
    overrides = overrides.inject([]) { |accum, override| accum << override.to_s }

    # Ensure we don't load the entire file into memory
    File.foreach(file_path) do |line|
      unless line
        next
      end
      _parse_line(line, config_hash, overrides)
    end

    # Turn the hash into an OpenStruct so settings can be accessed like properties
    OpenStruct.new(config_hash)

  end

  # Reads a config line and adds any settings to the config hash with respect to any
  # provided overrides.
  def _parse_line(line, config_hash, overrides)
    line.strip!
    line = _strip_comment(line)

    if line.empty?
      # Nothing to do here
      return
    end

    section = _get_section_title(line)
    if section
      _process_section(section, config_hash)
      return
    end

    key_value_hash = _get_key_value_hash(line)
    if key_value_hash
      unless $_current_section
        raise 'Key-value pair must be part of a section'
      end
      _process_key_value(key_value_hash, config_hash, overrides)
      return
    end

    raise 'Malformed config file: ' << line
  end

  # Strips the given line of any comment. For example,
  # >> _strip_comment("foo = bar ;this is a comment")
  # => "foo = bar"
  def _strip_comment(line)
    delimiter_indexes = (0 ... line.length).find_all { |i| line[i, 1] == COMMENT_DELIM }

    if delimiter_indexes.empty?
      # No comment to strip
      return line
    end

    # Ignore quoted strings by replacing them with a placeholder.
    # This is because a delimiter could occur in a string value.
    copy = String.new(line)
    line.scan(STRING_REGEX).each do |str|
      copy.sub!(str, ' ' * str.length)
    end

    # Take everything up to the first occurrence of COMMENT_DELIM
    comment_start = copy.index(COMMENT_DELIM)

    unless comment_start
      # No comment to strip
      return line
    end

    comment_start -= 1
    if comment_start < 0
      return ''
    end

    sanitized = line[0..comment_start]
    sanitized.strip!
    sanitized
  end

  # Parses and returns the section title from the line. Returns nil if the line is not a
  # section declaration.
  def _get_section_title(line)
    section_matcher = line.match(SECTION_REGEX)
    unless section_matcher
      return nil
    end

    section = section_matcher[0]

    # Remove the brackets around the name
    section = section[1..section.length - 2]

    if section =~ /\s/
      raise 'Section name may not contain whitespace: ' << section
    end

    section
  end

  # Processes the given section by adding a configuration for it to the config hash
  # and updating the current section.
  def _process_section(section, config_hash)
    if config_hash.has_key?(section)
      raise 'Duplicate section: ' << section
    end

    config_hash[section] = ConfigHash.new
    $_current_section = section
  end

  # Parses and returns the key-value pair from the line. Returns nil if the line is not a
  # key-value pair, otherwise returns a hash containing the key, value, and override name.
  # The override is nil if one is not specified.
  def _get_key_value_hash(line)
    unless line.include?(VALUE_ASSIGNMENT)
      return nil
    end

    if line.index(VALUE_ASSIGNMENT) == 0
      raise 'Invalid key: ' << line
    end

    assignment = line.index(VALUE_ASSIGNMENT)
    key = line[0..assignment - 1]

    value = line[assignment + 1..line.length]
    override = nil

    key.strip!
    value.strip!

    # Handle overrides
    if key.include?(OVERRIDE_START_DELIM) and key.end_with?(OVERRIDE_END_DELIM)
      start_index = key.index(OVERRIDE_START_DELIM)
      end_index = key.index(OVERRIDE_END_DELIM)
      override = key[start_index + 1..end_index - 1]
      key = key[0..start_index - 1]

      key.strip!
      override.strip!

      if key.empty? or override.empty?
        raise 'Invalid key: ' << line
      end
    end

    {:key => key, :value => value, :override => override}
  end

  # Processes the given key-value hash by adding the value assignment to the config hash.
  # The value is not added if there is an overriding value already set (unless the value
  # itself is overriding, in which case it's last-man-wins).
  def _process_key_value(key_value_hash, config_hash, overrides)
    key = key_value_hash[:key]
    value = key_value_hash[:value]
    override = key_value_hash[:override]

    unless config_hash.has_key?($_current_section)
      config_hash[$_current_section] = ConfigHash.new
    end

    # Do not set the value if it has been previously overridden
    if override.nil? and not $_overridden.include?($_current_section + key)
      config_hash[$_current_section][key] = _coerce_type(value)
    elsif overrides.include?(override)
      config_hash[$_current_section][key] = _coerce_type(value)
      $_overridden.add($_current_section + key)
    end
  end

  # Converts the given string value to the appropriate data type.
  def _coerce_type(value)
    # Handle quoted strings
    if value =~ STRING_REGEX
      return value[1..value.length - 2]
    end

    # Handle booleans
    if BOOLEANS.include?(value)
      return !!(value =~ BOOLEAN_TRUE_REGEX)
    end

    # Handle numeric values, coerce to int or float appropriately
    if _is_numeric?(value)
      value = Float(value)
      return value % 1.0 == 0 ? value.to_i : value
    end

    # Handle lists
    if value.include?(LIST_DELIM)
      array = []
      value.split(LIST_DELIM).each do |val|
        # Coerce each list value to its appropriate type
        array << _coerce_type(val)
      end
      return array
    end

    # Otherwise, just return the value as a string
    value
  end

  # Indicates if the given string is a numeric value.
  def _is_numeric?(str)
    Float(str) != nil rescue false
  end


  # Hash implementation which allows for property-like value lookup.
  # This shouldn't be used outside of this module due to its unsafe
  # nature.
  class ConfigHash < Hash

    def []=(key, value)
      super(key.to_sym, value)
    end

    def method_missing(method)
      self[method]
    end

  end

end