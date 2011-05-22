require 'fileutils'

class Translate::File
  attr_accessor :path
  attr_accessor :escape
  
  def initialize(path,escape=false)
    self.path = path
    self.escape = escape
  end
  
  def write(keys)
    temp_file = Tempfile.new('translate')
    File.open(temp_file.path, "w") do |file|
      keys_to_yaml(Translate::File.deep_stringify_keys(keys)).split("\n").each do |line|
        file.puts cleanup(line)
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
      keys.ya2yaml(:escape_as_utf8 => true)
    else
      keys.to_yaml
    end
  end

  # remove strings like "!ruby/object:Hash" and "!!null"
  # we don't need them and rails doesn't like them very much
  def cleanup(line)
    line.gsub!(/\s*\!ruby\/object:Hash\s*/, "")
    line.gsub!(/\s*\!\!null\s*/, "")
    line
  end

end
