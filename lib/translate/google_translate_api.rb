# Depends on httparty gem
# http://www.robbyonrails.com/articles/2009/03/16/httparty-goes-foreign
# TODO: this is probably not working, this API doesn't exist anymore
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
