require 'server/starter/version'
require 'puma/const'

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
        if Gem::Version.new(Puma::Const::PUMA_VERSION) < Gem::Version.new('5')
          ENV["PUMA_INHERIT_#{i}"] = "#{fd}:#{url}"
        else
          ENV['LISTEN_FDS'] = '1'
          ENV['LISTEN_PID'] = Process.pid.to_s
        end
        { fd: fd, url: url }
      end
    end
  end
end
