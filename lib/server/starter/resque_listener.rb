require 'server/starter/version'

class Server::Starter
  class ResqueListener
    # This allows a new master process to incrementally
    # phase out the old master process with SIGTTOU.
    # The last worker spawned will then kill off the old master
    # process with a SIGQUIT.
    #
    # @param starter [ResqueStarter]
    # @param worker [Resque::Worker]
    # @param worker_nr [Integer] worker number
    # @param status_file [String] path to Server::Starter status file (--status-file)
    def self.graceful_restart(starter, worker, worker_nr, status_file)
      pids = File.readlines(status_file).map {|_| _.chomp.split(':') }.to_h
      old_gen = ENV['SERVER_STARTER_GENERATION'].to_i - 1
      if old_pid = pids[old_gen.to_s]
        sig = (worker_nr + 1) >= starter.num_workers ? :QUIT : :TTOU
        Process.kill(sig, old_pid.to_i)
        while starter.old_workers.size > starter.num_workers
          sleep 0.1
        end
      end
    rescue Errno::ENOENT, Errno::ESRCH => e
      $stderr.puts "#{e.class} #{e.message}"
    end
  end
end
