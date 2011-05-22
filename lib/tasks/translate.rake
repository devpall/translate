require 'yaml'

class Hash
  def deep_merge(other)
    # deep_merge by Stefan Rusterholz, see http://www.ruby-forum.com/topic/142809
    merger = proc { |key, v1, v2| (Hash === v1 && Hash === v2) ? v1.merge(v2, &merger) : v2 }
    merge(other, &merger)
  end

  def set(keys, value)
    key = keys.shift
    if keys.empty?
      self[key] = value
    else
      self[key] ||= {}
      self[key].set keys, value
    end
  end

  # copy of ruby's to_yaml method, prepending sort.
  # before each so we get an ordered yaml file
  def to_yaml( opts = {} )
    YAML::quick_emit( self, opts ) do |out|
      out.map( taguri, to_yaml_style ) do |map|
        sort.each do |k, v| #<- Adding sort.
          map.add( k, v )
        end
      end
    end
  end
end

# Depends on httparty gem
# http://www.robbyonrails.com/articles/2009/03/16/httparty-goes-foreign
class GoogleApi
  include HTTParty
  base_uri 'ajax.googleapis.com'

  def self.fix_translation(string)
    string.gsub!(/(\S)%\s({[^}]*})/, '\1 %\2') # "My% {model}" => "My %{model}"
    string.gsub!(/%\s({[^}]*})/, '%\1')        # "% {model}" => "%{model}"
    string.gsub!(/({[^}]*})%/, '%\1')          # "{model}%" => "%{model}"

    tparams = string.to_s.scan(/%{[^}]*}/)                       # translated params
    tparams.each_with_index { |p,i| string.sub!(p, @params[i]) } # restore the original params

    string
  end

  def self.translate(string, to, from)
    @params = string.to_s.scan(/%{[^}]*}/) # list of params like "%{model}"

    tries = 0
    begin
      response = get("/ajax/services/language/translate",
          :query => {:langpair => "#{from}|#{to}", :q => string, :v => 1.0},
          :format => :json)
    rescue
      tries += 1
      puts("SLEEPING - retrying in 5s...")
      sleep(5)
      retry if tries < 10
    end

    unless response.nil? || response["responseData"].nil? || response["responseData"]["translatedText"].nil?
      fix_translation(response["responseData"]["translatedText"])
    else
      ""
    end
  end
end

# Examples:
#
#  * Find strings that exist in en but not in pt-br:
#    BASE=en LOCALE=pt-br rake translate:untranslated
#  * Find strings that exist in en but not in pt-br, translates them (google translate) and add to pt-br.yml:
#    TRANSLATE=1 BASE=en LOCALE=pt-br rake translate:add_untranslated
#  * Find strings being used in the application but that are not in en.ym:
#    LOCALE=en rake translate:missing
#  * Checks for all strings in the locale en and saves them in a standard en.yml file:
#    LOCALE=en rake translate:cleanup
#
# Other env options:
#   TRANSLATE=1  # translate with google code
#
namespace :translate do

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

  desc "Read all strings ENV['LOCALE'] and saves them sorted and with standard YAML formatting"
  task :cleanup => :environment do
    locale = ENV['LOCALE'].to_sym || I18n.default_locale
    puts "* Cleaning up and formatting the locale: " + locale.to_s

    I18n.backend.send(:init_translations)
    Translate::Storage.new(locale).write_to_file
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





  desc "Remove all translation texts that are no longer present in the locale they were translated from"
  task :remove_obsolete_keys => :environment do
    I18n.backend.send(:init_translations)
    master_locale = ENV['LOCALE'] || I18n.default_locale
    Translate::Keys.translated_locales.each do |locale|
      texts = {}
      Translate::Keys.new.i18n_keys(locale).each do |key|
        if I18n.backend.send(:lookup, master_locale, key).to_s.present?
          texts[key] = I18n.backend.send(:lookup, locale, key)
        end
      end
      I18n.backend.send(:translations)[locale] = nil # Clear out all current translations
      I18n.backend.store_translations(locale, Translate::Keys.to_deep_hash(texts))
      Translate::Storage.new(locale).write_to_file      
    end
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
