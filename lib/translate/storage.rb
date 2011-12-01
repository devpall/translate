class Translate::Storage
  attr_accessor :locale
  
  def initialize(locale)
    self.locale = locale.to_sym
  end
  
  def write_to_file
    Translate::File.new(file_path).write(hash_without_base)
  end
  
  def self.file_paths(locale)
    Dir.glob(File.join(root_dir, "config", "locales", locale.to_s, "**","#{locale}.yml"))
  end
  
  def self.root_dir
    Rails.root
  end
  
  private
  def keys
    {locale => I18n.backend.send(:translations)[locale]}
  end

  def base_keys
    base = YAML.load_file(File.join(Translate::Storage.root_dir, "config", "locales", locale.to_s, "base.#{locale}.yml"))
    base.recursive_symbolize_keys!
    base[locale].keys
  end

  def hash_without_base
    remainder = Hash.new(locale)
    remainder[locale] = keys[locale].slice!(*base_keys)
    remainder
  end
  
  def file_path
    File.join(Translate::Storage.root_dir, "config", "locales", locale.to_s, "#{locale}.yml")
  end
end
