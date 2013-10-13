require 'test/unit'
require 'config'
include Config

# Some basic unit tests to ensure load_config conforms to the API specification.
class TestConfig < Test::Unit::TestCase

  # Verify load_config blows up when a bad file path is given.
  def test_empty_path
    e = assert_raise(RuntimeError) { load_config('bad file path') }
    assert_equal('Invalid file path: bad file path', e.message)
  end

  # Verify load_config loads the correct values when no overrides are provided.
  def test_no_overrides
    config = load_config('test_configs/good-config.conf')

    assert_equal(26214400, config.common.basic_size_limit)
    assert_equal(52428800, config.common.student_size_limit)
    assert_equal(2147483648, config.common.paid_users_size_limit)
    assert_equal('/srv/var/tmp/', config.common.path)
    assert_equal('hello there, ftp uploading', config.ftp.name)
    assert_equal('/tmp/', config.ftp.path)
    assert_equal('/tmp/', config.ftp[:path])
    assert_equal(false, config.ftp.enabled)
    assert_equal('http uploading', config.http.name)
    assert_equal('/tmp/', config.http.path)
    assert_equal(%w(array of values), config.http.params)
    assert_equal({:name => 'hello there, ftp uploading', :path => '/tmp/', :enabled => false}, config.ftp)
    assert_equal(true, config.http[:'foo bar'])
    assert_nil(config.ftp.foo)
  end

  # Verify load_config loads the correct values when overrides are provided.
  def test_with_overrides
    config = load_config('test_configs/good-config.conf', ['ubuntu', :production, 'itscript'])

    assert_equal(26214400, config.common.basic_size_limit)
    assert_equal(52428800, config.common.student_size_limit)
    assert_equal(2147483648, config.common.paid_users_size_limit)
    assert_equal('/srv/tmp/', config.common.path)
    assert_equal('hello there, ftp uploading', config.ftp.name)
    assert_equal('/etc/var/uploads', config.ftp.path)
    assert_equal('/etc/var/uploads', config.ftp[:path])
    assert_equal(true, config.ftp.enabled)
    assert_equal('http uploading', config.http.name)
    assert_equal('/srv/var/tmp/', config.http.path)
    assert_equal(%w(array of values), config.http.params)
    assert_equal({:name => 'hello there, ftp uploading', :path => '/etc/var/uploads', :enabled => true}, config.ftp)
    assert_equal(false, config.http[:'foo bar'])
    assert_nil(config.ftp.foo)
  end

  # Verify load_config handles empty values.
  def test_empty_string
    config = load_config('test_configs/empty-value-config.conf')

    assert_equal(26214400, config.common.basic_size_limit)
    assert_equal('', config.common.student_size_limit)
  end

  # Verify load_config blows up when a malformed config file is provided such that it
  # has no sections specified.
  def test_no_sections
    e = assert_raise(RuntimeError) { load_config('test_configs/no-sections-config.conf') }
    assert_equal('Key-value pair must be part of a section', e.message)
  end

  # Verify load_config blows up when a malformed config file is provided such that it
  # has an invalid override key.
  def test_invalid_override
    e = assert_raise(RuntimeError) { load_config('test_configs/bad-override-config.conf') }
    assert_equal('Invalid key: path<> = /srv/var/tmp/', e.message)
  end

  # Verify load_config blows up when a malformed config file is provided such that it
  # has an invalid key.
  def test_invalid_key
    e = assert_raise(RuntimeError) { load_config('test_configs/bad-key-config.conf') }
    assert_equal('Invalid key: = /srv/var/tmp/', e.message)
  end

  # Verify load_config blows up when a malformed config file is provided such that it
  # has a section with whitespace in the name.
  def test_whitespace_section
    e = assert_raise(RuntimeError) { load_config('test_configs/whitespace-section-config.conf') }
    assert_equal('Section name may not contain whitespace: common foo', e.message)
  end

  # Verify load_config blows up when a malformed config file is provided such that it
  # has duplicate sections.
  def test_duplicate_section
    e = assert_raise(RuntimeError) { load_config('test_configs/duplicate-section-config.conf') }
    assert_equal('Duplicate section: common', e.message)
  end

  # Verify load_config blows up when a malformed config file is provided such that it
  # has an invalid key-value assignment.
  def test_invalid_pair
    e = assert_raise(RuntimeError) { load_config('test_configs/bad-pair-config.conf') }
    assert_equal('Malformed config file: basic_size_limit: 26214400', e.message)
  end

end