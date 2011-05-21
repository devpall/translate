require 'fileutils'

class Translate::File
  attr_accessor :path
  attr_accessor :escape
  
  def initialize(path,escape=false)
    self.path = path
    self.escape = escape
  end
  
  def write(keys)
    FileUtils.mkdir_p File.dirname(path)
    File.open(path, "w") do |file|
      file.puts keys_to_yaml(Translate::File.deep_stringify_keys(keys))
    end
    # little hack to remove the string "!ruby/object:Hash" that rails doesn't like very much
    system "sed -i 's: \\!ruby/object\\:Hash::g' #{path}"
    system "sed -i 's: \\!\\!null::g' #{path}"
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
end
