require 'server/starter/version'

class Server::Starter
  class PumaListener
    def self.listen
      $stderr.puts "Configure ENV in config seems too late. Use start_puma.rb instead"
    end
  end
end
