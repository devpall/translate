# -*- coding: utf-8 -*-
class Translate::Storage
  attr_accessor :locale

  def initialize(locale)
    self.locale = locale.to_sym
  end

  # remove the keys not used in the project from the loaded keys and
  # save the result in the target file 'target' or the default path if not informed
  def remove_unused_keys_and_write_to_file(target=nil, search_pattern=nil)
    save_to = target.nil? ? file_path : target
    keys_to_write = remove_unused_keys(save_to, search_pattern)
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

  # remove the keys in the 'source' file who are not present in the 'model' file
  # save the result in the 'source' file
  def remove_deleted_keys_and_write_to_file(source=nil, model=nil)
    save_to = source
    keys_to_write = source_without_deleted_keys_in_origin(source,model)
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

  # creates a hash with all keys used in the project
  def project_used_keys(search_pattern=nil)
    regex = /(I18n.| |\>|\(|=|\[|\{|I18n::|,|\+)t[( ]?([\"\'][a-zA-Z0-9._]+[\"\'])(, :count => [@a-zA-Z0-9.]+|)[)]?/
    search_pattern ||= 'app/**/*.{rb,erb}'

    keys = Hash.new
    Dir[search_pattern].each do |path|
      File.open( path ) do |f|
        f.grep(regex) do |line|
          i18n_call = line.scan(regex)
          i18n_call.each do |k|
            key = k[1]
            key.delete! "\"\'"
            key.insert(0,locale.to_s+'.')
            if k[2].include? ":count"
              keys[(key+'.'+'zero').to_sym]  = 0
              keys[(key+'.'+'one').to_sym]  = 0
              keys[(key+'.'+'two').to_sym]  = 0
              keys[(key+'.'+'few').to_sym]  = 0
              keys[(key+'.'+'many').to_sym]  = 0
              keys[(key+'.'+'other').to_sym]  = 0
            else
              keys[key.to_sym] = 0
            end
          end
        end
      end
    end
    keys
  end

  # remove unused keys in the file 'path'
  def remove_unused_keys(path,search_pattern=nil)
    file_keys = YAML.load_file(path)
    file_keys_shallow = Translate::Keys.to_shallow_hash(file_keys)
    project_keys = Translate::Keys.to_shallow_hash(project_used_keys(search_pattern))

    to_save_shallow = file_keys_shallow.slice(*project_keys.keys)
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

  #remove the keys not present in 'model' file from 'source' file
  def source_without_deleted_keys_in_origin(source,model)
    source_keys = YAML.load_file(source)
    model_keys = YAML.load_file(model)

    source_keys_shallow = Translate::Keys.to_shallow_hash(source_keys)
    model_keys_shallow = Translate::Keys.to_shallow_hash(model_keys)

    to_save_shallow = source_keys_shallow.slice(*model_keys_shallow.keys)
    Translate::Keys.to_deep_hash(to_save_shallow)
  end

  def base_file_path
    File.join(Translate::Storage.root_dir, "config", "locales", "base.yml")
  end

  def file_path
    File.join(Translate::Storage.root_dir, "config", "locales", "#{locale}.yml")
  end
end
