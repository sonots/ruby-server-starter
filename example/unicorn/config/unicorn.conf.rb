require 'server/starter/unicorn_listener'
listener = Server::Starter::UnicornListener

worker_processes  2
preload_app true
 
APP_ROOT = File.expand_path('../..', __FILE__)
status_file = File.join(APP_ROOT, 'log/start_server.stat')

fd = listener.listen # Configure UNICORN_FD ENV
unless fd
  # Fallback if not running under Server::Starter
  listen ENV['PORT'] || '10080'
end
 
before_fork do |server, worker|
  defined?(ActiveRecord::Base) and
    ActiveRecord::Base.connection.disconnect!
 
  # Throttle the master from forking too quickly by sleeping.  Due
  # to the implementation of standard Unix signal handlers, this
  # helps (but does not completely) prevent identical, repeated signals
  # from being lost when the receiving process is busy.
  sleep 1
end
 
after_fork do |server, worker|
  defined?(ActiveRecord::Base) and
    ActiveRecord::Base.establish_connection

  # This is optional
  #
  # This allows a new master process to incrementally
  # phase out the old master process with SIGTTOU to avoid a
  # thundering herd (especially in the "preload_app false" case)
  # when doing a transparent upgrade.  The last worker spawned
  # will then kill off the old master process with a SIGQUIT.
  listener.slow_start(server, worker, status_file)
end
