require 'yaml'

# Usage examples
# For more see: https://github.com/mconf/translate/wiki
#
#  Task 'cleanup':
#  * Checks for all strings in the locale en and saves them in a standard yaml file:
#    LOCALE=en rake translate:cleanup
#  * Cleanup config/locales/en/mconf.yml. Will write to it only the keys that are already in the file:
#    LOCALE=en FILE=config/locales/en/mconf.yml FILTER=1 bundle exec rake translate:cleanup
#
#  Task 'remove_keys':
#  * Remove the keys in the file config/locales/base.yml from the loaded keys and save it to config/locales/en.yml:
#    LOCALE=en bundle exec rake translate:remove_keys
#  * Remove the keys in the file config/locales/en/base.yml from the loaded keys and save it to config/locales/en/mconf.yml:
#    BASE=config/locales/en/base.yml FILE=config/locales/en/mconf.yml LOCALE=en bundle exec rake translate:remove_keys
#
namespace :translate do

  desc "Read all strings ENV['LOCALE'] and saves them sorted and with standard YAML formatting"
  task :cleanup => :environment do
    locale = ENV['LOCALE'].to_sym || I18n.default_locale
    to_file = ENV['FILE']
    filter = ENV['FILTER'] == "1"
    puts "* Cleaning up and formatting the locale: " + locale.to_s
    puts "* Saving to file: " + to_file unless to_file.nil?
    puts "* Saving only the keys already existent" if filter

    I18n.backend.send(:init_translations)
    Translate::Storage.new(locale).write_to_file(to_file, filter)
  end

  desc "Read all strings ENV['LOCALE'], remove the keys in a base file and saves them sorted and with standard YAML formatting"
  task :remove_keys => :environment do
    locale = ENV['LOCALE'].to_sym || I18n.default_locale
    base = ENV['BASE']
    to_file = ENV['FILE']
    puts "* Removing keys in the locale" + locale.to_s
    puts "* Removing the keys in: " + base unless base.nil?
    puts "* Saving to file: " + to_file unless to_file.nil?

    I18n.backend.send(:init_translations)
    Translate::Storage.new(locale).remove_keys_and_write_to_file(base, to_file)
  end

  desc "Read all strings ENV['SOURCE'], remove all the keys not present in ENV['MODEL'] and saves them sorted and with standard YAML formatting"
  task :remove_deleted_keys => :environment do
    locale = ENV['LOCALE']
    source = ENV['SOURCE']
    model = ENV['MODEL']
    puts "* Removing deleted keys from " + model + " in " + source
    puts "* Saving to file: " +  source

    I18n.backend.send(:init_translations)

    Translate::Storage.new(locale).remove_deleted_keys_and_write_to_file(source,model)
  end

  desc "Finds all strings referenced in the files in app/**/*, compares them with the strings in ENV['FILE']" \
       "and saves only the keys existent in both hashes. Will remove keys in the file that are not used in the project."
  task :remove_unused_keys => :environment do
    locale = ENV['LOCALE'].to_sym || I18n.default_locale
    to_file = ENV['FILE']
    search_pattern = ENV['PATTERN']

    puts "* Removing unused keys in the locale " + locale.to_s
    puts "* Saving to file: " + to_file unless to_file.nil?
    puts "* Search pattern: " + search_pattern unless search_pattern.nil?
    puts "* Saving only the keys used in the project"

    I18n.backend.send(:init_translations)
    Translate::Storage.new(locale).remove_unused_keys_and_write_to_file(to_file, search_pattern)
  end

  # TODO the tasks below should be verified and fixed if they're not working

  desc "Show untranslated keys for locale ENV['LOCALE'] (defaults to all locales) compared to ENV['BASE']"
  task :untranslated => :environment do
    locale = ENV['LOCALE'].to_sym || nil
    base_locale = ENV['BASE'].to_sym || I18n.default_locale
    puts "* Untranslated keys for locale: " + locale.to_s + " (base locale: " + base_locale.to_s + ")"

    untranslated = Translate::Keys.new.untranslated_keys(base_locale, locale)
    messages = []
    untranslated.each do |loc, keys|
      keys.each do |key|
        from_text = I18n.backend.send(:lookup, base_locale, key)
        messages << "#{loc}.#{key} (#{base_locale}.#{key}='#{from_text}')"
      end
    end

    if messages.present?
      messages.each { |m| puts m }
    else
      puts "No untranslated keys"
    end
  end

  desc "Show I18n keys that are being used but are missing in the ENV['LOCALE']"
  task :missing => :environment do
    locale = ENV['LOCALE'].to_sym || I18n.default_locale
    puts "* Missing keys in locale: " + locale.to_s

    missing = Translate::Keys.new.missing_keys(locale).inject([]) do |keys, (key, filename)|
      keys << "#{key} \t in #{filename} is missing"
    end
    puts missing.present? ? missing.join("\n") : "No missing translations in the locale " + locale.to_s
  end

  desc "Check untranslated strings (using rake translate:untranslated), translate them with google translate and add to the ENV['LOCALE']"
  task :add_untranslated => :environment do
    locale = ENV['LOCALE'].to_sym || I18n.default_locale
    base_locale = ENV['BASE'].to_sym || I18n.default_locale
    puts "* Adding untranslated keys in locale: " + locale.to_s + " (base locale: " + base_locale.to_s + ")"

    I18n.backend.send(:init_translations)
    texts = Translate::Keys.to_shallow_hash(I18n.backend.send(:translations)[locale])
    untranslated = Translate::Keys.new.untranslated_keys(base_locale, locale)
    untranslated.each do |loc, keys|
      keys.each do |key|
        value = I18n.backend.send(:lookup, base_locale, key)
        if ENV['TRANSLATE']
          translation = GoogleApi.translate(value, locale.to_s, base_locale.to_s)
          unless translation.blank?
            puts "Adding #{locale}.#{key}: #{translation} (translated from \"#{value}\")"
            value = translation
          else
            puts "Adding #{locale}.#{key}: #{translation} (could not translate)"
          end
        else
          puts "Adding #{locale}.#{key}: #{value}"
        end
        texts[key] = value
      end
    end
    I18n.backend.send(:translations)[locale] = nil # Clear out all current translations
    I18n.backend.store_translations(locale, Translate::Keys.to_deep_hash(texts))
    Translate::Storage.new(locale).write_to_file
  end

  desc "Merge I18n keys from log/translations.yml into config/locales/*.yml (for use with the Rails I18n TextMate bundle)"
  task :merge_keys => :environment do
    I18n.backend.send(:init_translations)
    new_translations = YAML::load(IO.read(File.join(Rails.root, "log", "translations.yml")))
    raise("Can only merge in translations in single locale") if new_translations.keys.size > 1
    locale = new_translations.keys.first

    overwrites = false
    Translate::Keys.to_shallow_hash(new_translations[locale]).keys.each do |key|
      new_text = key.split(".").inject(new_translations[locale]) { |hash, sub_key| hash[sub_key] }
      existing_text = I18n.backend.send(:lookup, locale.to_sym, key)
      if existing_text && new_text != existing_text
        puts "ERROR: key #{key} already exists with text '#{existing_text.inspect}' and would be overwritten by new text '#{new_text}'. " +
          "Set environment variable OVERWRITE=1 if you really want to do this."
        overwrites = true
      end
    end

    if !overwrites || ENV['OVERWRITE']
      I18n.backend.store_translations(locale, new_translations[locale])
      Translate::Storage.new(locale).write_to_file
    end
  end

  desc "Apply Google translate to auto translate all texts in locale ENV['FROM'] to locale ENV['TO']"
  task :google => :environment do
    raise "Please specify FROM and TO locales as environment variables" if ENV['FROM'].blank? || ENV['TO'].blank?

    I18n.backend.send(:init_translations)

    start_at = Time.now
    translations = {}
    Translate::Keys.new.i18n_keys(ENV['FROM']).each do |key|
      from_text = I18n.backend.send(:lookup, ENV['FROM'], key).to_s
      to_text = I18n.backend.send(:lookup, ENV['TO'], key)
      if !from_text.blank? && to_text.blank?
        print "#{key}: '#{from_text[0, 40]}' => "
        if !translations[from_text]
          response = GoogleApi.translate(from_text, ENV['TO'], ENV['FROM'])
          translations[from_text] = response["responseData"] && response["responseData"]["translatedText"]
        end
        if !(translation = translations[from_text]).blank?
          translation.gsub!(/\(\(([a-z_.]+)\)\)/i, '{{\1}}')
          # Google translate sometimes replaces {{foobar}} with (()) foobar. We skip these
          if translation !~ /\(\(\)\)/
            puts "'#{translation[0, 40]}'"
            I18n.backend.store_translations(ENV['TO'].to_sym, Translate::Keys.to_deep_hash({key => translation}))
          else
            puts "SKIPPING since interpolations were messed up: '#{translation[0,40]}'"
          end
        else
          puts "NO TRANSLATION - #{response.inspect}"
        end
      end
    end

    puts "\nTime elapsed: #{(((Time.now - start_at) / 60) * 10).to_i / 10.to_f} minutes"
    Translate::Storage.new(ENV['TO'].to_sym).write_to_file
  end

  desc "List keys that have changed I18n texts between YAML file ENV['FROM_FILE'] and YAML file ENV['TO_FILE']. Set ENV['VERBOSE'] to see changes"
  task :changed => :environment do
    from_hash = Translate::Keys.to_shallow_hash(Translate::File.new(ENV['FROM_FILE']).read)
    to_hash = Translate::Keys.to_shallow_hash(Translate::File.new(ENV['TO_FILE']).read)
    from_hash.each do |key, from_value|
      if (to_value = to_hash[key]) && to_value != from_value
        key_without_locale = key[/^[^.]+\.(.+)$/, 1]
        if ENV['VERBOSE']
          puts "KEY: #{key_without_locale}"
          puts "FROM VALUE: '#{from_value}'"
          puts "TO VALUE: '#{to_value}'"
        else
          puts key_without_locale
        end
      end
    end
  end
end
