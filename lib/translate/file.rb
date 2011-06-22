require 'fileutils'
require 'ya2yaml'

class Translate::File
  attr_accessor :path
  attr_accessor :escape

  def initialize(path,escape=true)
    self.path = path
    self.escape = escape
  end

  def write(keys)
    temp_file = Tempfile.new('translate')
    File.open(temp_file.path, "w") do |file|
      keys_to_yaml(Translate::File.deep_stringify_keys(keys)).split("\n").each do |line|
        file.puts line
      end
    end
    FileUtils.mkdir_p File.dirname(path)
    FileUtils.mv(temp_file.path, path)
  end

  def read
    File.exists?(path) ? YAML::load(IO.read(path)) : {}
  end

  # Stringifying keys for prettier YAML
  def self.deep_stringify_keys(hash)
    hash.inject({}) { |result, (key, value)|
      value = deep_stringify_keys(value) if value.is_a? Hash
      result[(key.to_s rescue key) || key] = value
      result
    }
  end

  private

  def keys_to_yaml(keys)
    # Using ya2yaml, if available, for UTF8 support
    if keys.respond_to?(:ya2yaml) && self.escape
      keys.ya2yaml(:syck_compatible => true)
    else
      keys.to_yaml
    end
  end

end
