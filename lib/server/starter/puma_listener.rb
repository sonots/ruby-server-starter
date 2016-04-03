require 'server/starter/version'

class Server::Starter
  class PumaListener
    def self.listen
      return nil unless ENV.key?('SERVER_STARTER_PORT')
      ENV['SERVER_STARTER_PORT'].split(';').map.with_index do |x, i|
        path_or_port, fd = x.split('=', 2)
        if path_or_port.match(/(?:^|:)\d+$/)
          url = "tcp://#{path_or_port}"
        else
          url = "unix://#{path_or_port}"
        end
        ENV["PUMA_INHERIT_#{i}"] = "#{fd}:#{url}"
        { fd: fd, url: url }
      end
    end
  end
end
