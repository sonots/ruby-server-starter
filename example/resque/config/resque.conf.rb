require 'server/starter/resque_listener'
listener = Server::Starter::ResqueListener
APP_ROOT = File.expand_path('../..', __FILE__)

concurrency 2
queues ['test']
pid_file File.join(APP_ROOT, 'log/start_resque.pid')
status_file File.join(APP_ROOT, 'log/start_resque.stat')

# preload rails app
# require File.join(APP_ROOT, 'config/environment')
# Rails.application.eager_load!

start_server_status_file = File.join(APP_ROOT, 'log/start_server.stat')

before_fork do |starter, worker, worker_nr|
  defined?(ActiveRecord::Base) and
    ActiveRecord::Base.connection.disconnect!

  sleep 1
end

after_fork do |starter, worker, worker_nr|
  defined?(ActiveRecord::Base) and
    ActiveRecord::Base.establish_connection

  # Graceful restart
  #
  # This allows a new master process to incrementally
  # phase out the old master process with SIGTTOU.
  # The last worker spawned # will then kill off the old master
  # process with a SIGQUIT.
  listener.graceful_restart(starter, worker, worker_nr, start_server_status_file)
end
