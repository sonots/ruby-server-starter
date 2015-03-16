class Server::Starter
  class UnicornListener
    # Map ENV['SERVER_STARTER_PORT'] to ENV['UNICORN_FD']
    def self.listen
      return nil unless ENV.key?('SERVER_STARTER_PORT')
      fds = ENV['SERVER_STARTER_PORT'].split(';').map { |x|
        path_or_port, fd = x.split('=', 2)
        fd
      }
      ENV['UNICORN_FD'] = fds.join(',')
    end

    # This allows a new master process to incrementally
    # phase out the old master process with SIGTTOU to avoid a
    # thundering herd (especially in the "preload_app false" case)
    # when doing a transparent upgrade.  The last worker spawned
    # will then kill off the old master process with a SIGQUIT.
    #
    # @param server [Unicorn::HttpServer]
    # @param worker [Unicorn::Worker]
    # @param status_file [String] path to Server::Starter status file (--status-file)
    def self.slow_start(server, worker, status_file)
      pids = File.readlines(status_file).map {|_| _.chomp.split(':') }.to_h
      old_gen = ENV['SERVER_STARTER_GENERATION'].to_i - 1
      if old_pid = pids[old_gen.to_s]
        sig = (worker.nr + 1) >= server.worker_processes ? :QUIT : :TTOU
        Process.kill(sig, old_pid.to_i)
      end
    rescue Errno::ENOENT, Errno::ESRCH => e
      $stderr.puts "#{e.class} #{e.message}"
    end
  end
end
