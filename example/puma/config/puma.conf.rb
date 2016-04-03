APP_ROOT = File.expand_path('../..', __FILE__)
status_file = File.join(APP_ROOT, 'log/start_server.stat')

pidfile File.join(APP_ROOT, 'log/puma.pid')
state_path File.join(APP_ROOT, 'log/puma.state')

# prune_bundler # need to tweak lib/puma/launher to add { close_others: false } opts to Kernel.exec
preload_app!

# Configure "min" to be the minimum number of threads to use to answer
# requests and "max" the maximum.
# The default is "0, 16".
threads 0, 16

# How many worker processes to run. The default is "0".
workers 2

# Run puma via start_puma.rb to configure PUMA_INHERIT_\d ENV from SERVER_STARTER_PORT ENV as
# $ bundle exec --keep-file-descriptors start_puma.rb puma -C config/puma.conf.rb config.ru
if ENV['PUMA_INHERIT_0']
  ENV.each do |k,v|
    if k =~ /PUMA_INHERIT_\d+/
      fd, url = v.split(":", 2)
      bind url
    end
  end
else
  # Fallback if not running under Server::Starter
  bind 'tcp://0.0.0.0:10080'
end

# Code to run before doing a restart. This code should
# close log files, database connections, etc.
# This can be called multiple times to add code each time.
on_restart do
  puts 'On restart...'
end

# Code to run when a worker boots to setup the process before booting
# the app. This can be called multiple times to add hooks.
on_worker_boot do
  defined?(ActiveRecord::Base) and ActiveRecord::Base.connection.disconnect!
end

# Code to run when a worker boots to setup the process after booting
# the app. This can be called multiple times to add hooks.
after_worker_boot do
  defined?(ActiveRecord::Base) and ActiveRecord::Base.establish_connection
end

# Code to run when a worker shutdown.
on_worker_shutdown do
  puts 'On worker shutdown...'
end
