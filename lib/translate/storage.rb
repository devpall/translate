class Translate::Storage
  attr_accessor :locale

  def initialize(locale)
    self.locale = locale.to_sym
  end

  # remove the keys not present in the project from the loaded keys and
  # save the result in the target file 'target' or the default path if not informed
  def cleaning_keys_and_write_to_file(target=nil)
    save_to = target.nil? ? file_path : target
    keys_to_write = remove_not_used_keys(save_to)
    Translate::File.new(save_to).write(keys_to_write)
  end

  # remove the keys in the file 'base' from the loaded keys and
  # save the result in the target file 'target' or the default path if not informed
  def remove_keys_and_write_to_file(base=nil, target=nil)
    save_to = target.nil? ? file_path : target
    base_file = base.nil? ? base_file_path : base
    keys_to_write = keys_without_base_file(base_file)
    Translate::File.new(save_to).write(keys_to_write)
  end

  # save the loaded keys in the target file 'target' or the default path if not informed
  # if maintain_keys is true, will only save the keys already existent in the target file
  def write_to_file(target=nil, maintain_keys=false)
    save_to = target.nil? ? file_path : target
    keys_to_write = maintain_keys ? keys_from_file(save_to) : keys
    Translate::File.new(save_to).write(keys_to_write)
  end

  def self.file_paths(locale)
    Dir.glob(File.join(root_dir, "config", "locales", "**", "#{locale}.yml"))
  end

  def self.root_dir
    Rails.root
  end

  private

  def keys
    {locale => I18n.backend.send(:translations)[locale]}
  end

  # create the file with all keys used in the project
  def create_file_with_used_keys
    Dir['app/**/*.{ rb,erb}'].each do |path|
      File.open( path ) do |f|
        f.grep(/(I18n.| )t[(][\"\'][a-zA-Z0-9._]+[\"\'][)]/) do |line|
          i18n_call = line.match(/(I18n.| )t[(][\"\'][a-zA-Z0-9._]+[\"\'][)]/)[0]
          key = i18n_call.match(/[\"\'][a-zA-Z0-9._]+[\"\']/).to_s
          key.delete! "\"\'"
          key = key.insert(0,'en.')
          
        end
      end
    end
  end

  # remove all not used keys in the file 'path'
  def remove_not_used_keys(path)
    file_keys = YAML.load(path)
    file_keys_shallow = Translate::Keys.to_shallow_hash(file_keys)
    project_keys = create_file_with_used_keys

    to_save_shallow = file_keys_shallow,slice(*project_keys.keys)
    Translate::Keys.to_deep_hash(to_save_shallow)
  end

  # filter the hash 'keys' with only the keys existent in the file 'path'
  def keys_from_file(path)
    file_keys = YAML.load_file(path)
    file_keys_shallow = Translate::Keys.to_shallow_hash(file_keys)

    keys_shallow = Translate::Keys.to_shallow_hash(keys)

    to_save_shallow = keys_shallow.slice(*file_keys_shallow.keys)
    Translate::Keys.to_deep_hash(to_save_shallow)
  end

  # remove the keys in the 'base' file from the keys loaded
  def keys_without_base_file(base)
    file_keys = YAML.load_file(base)
    file_keys_shallow = Translate::Keys.to_shallow_hash(file_keys)

    keys_shallow = Translate::Keys.to_shallow_hash(keys)

    to_save_shallow = keys_shallow.slice!(*file_keys_shallow.keys)
    Translate::Keys.to_deep_hash(to_save_shallow)
  end

  def base_file_path
    File.join(Translate::Storage.root_dir, "config", "locales", "base.yml")
  end

  def file_path
    File.join(Translate::Storage.root_dir, "config", "locales", "#{locale}.yml")
  end
end
