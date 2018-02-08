# ruby-server-starter

a superdaemon for hot-deploying server programs (ruby port of [p5-Server-Starter](https://github.com/kazuho/p5-Server-Starter))

# Description

*note: this description is almost entirely taken from the original Server::Starter module*

The ```start_server``` utility is a superdaemon for hot-deploying server programs.

It is often a pain to write a server program that supports graceful restarts, with no resource leaks. Server::Starter solves the problem by splitting the task into two: ```start_server``` works as a superdaemon that binds to zero or more TCP ports or unix sockets, and repeatedly spawns the server program that actually handles the necessary tasks (for example, responding to incoming commenctions). The spawned server programs under ```start_server``` call accept(2) and handle the requests.

To gracefully restart the server program, send SIGHUP to the superdaemon. The superdaemon spawns a new server program, and if (and only if) it starts up successfully, sends SIGTERM to the old server program.

By using ```start_server``` it is much easier to write a hot-deployable server. Following are the only requirements a server program to be run under ```start_server``` should conform to:

- receive file descriptors to listen to through an environment variable
- perform a graceful shutdown when receiving SIGTERM

# Unicorn

Following is an example to run unicorn server under ```Server::Starter```.

The command line example:

```
bundle exec start_server.rb \
  --port=10080 \
  --signal-on-hup=CONT \
  --dir=/path/to/app \
  --status-file=/path/to/app/log/start_server.stat \
  --pid-file=/path/to/app/log/start_server.pid \
  -- \
  bundle exec --keep-file-descriptors unicorn -c config/unicorn.conf.rb config.ru
```

An example of unicorn.conf:

```ruby
require 'server/starter/unicorn_listener'
listener = Server::Starter::UnicornListener

worker_processes  2
preload_app true
 
APP_ROOT = File.expand_path('../..', __FILE__)
status_file = File.join(APP_ROOT, 'log/start_server.stat')

fd = listener.listen
unless fd
  # Fallback if not running under Server::Starter
  listen ENV['PORT'] || '10080'
end
 
before_fork do |server, worker|
  defined?(ActiveRecord::Base) and ActiveRecord::Base.connection.disconnect!
 
  # Throttle the master from forking too quickly by sleeping.  Due
  # to the implementation of standard Unix signal handlers, this
  # helps (but does not completely) prevent identical, repeated signals
  # from being lost when the receiving process is busy.
  sleep 1
end
 
after_fork do |server, worker|
  defined?(ActiveRecord::Base) and ActiveRecord::Base.establish_connection

  # This is optional
  #
  # This allows a new master process to incrementally
  # phase out the old master process with SIGTTOU to avoid a
  # thundering herd (especially in the "preload_app false" case)
  # when doing a transparent upgrade.  The last worker spawned
  # will then kill off the old master process with a SIGQUIT.
  listener.slow_start(server, worker, status_file)
end
```

# Puma

Following is an example to run puma server under ```Server::Starter```.

The command line example:

```
bundle exec start_server.rb \
  --port=0.0.0.0:10080 \
  --dir=/path/to/app \
  --interval=1 \
  --signal-on-hup=TERM \
  --signal-on-TERM=TERM \
  --pid-file=/path/to/app/log/start_server.pid \
  --status-file=/path/to/app/log/start_server.stat \
  --envdir=env \
  --enable-auto-restart \
  --auto-restart-interval=100 \
  --kill-old-delay=10 \
  --backlog=100 \
  -- \
  bundle exec --keep-file-descriptors start_puma.rb puma -C config/puma.rb config.ru
```

An example of config/puma.rb:

```ruby

require 'server/starter/puma_listener'
listener = ::Server::Starter::PumaListener

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
if ENV['SERVER_STARTER_PORT']
  puma_inherits = listener.listen
  puma_inherits.each do |puma_inherit|
    bind puma_inherit[:url]
  end
else
  puts '[WARN] Fallback to 0.0.0.0:10080 since not running under Server::Starter'
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
```

## Options

To be written

### --envdir [dir]

Configure environment variables from files on given directory, and reload on restarting.

The directory structure is inspired from [envdir](https://cr.yp.to/daemontools/envdir.html) of daemontools.
The filename is the environment variable name, and its content (first line) is the value of the environment variable.

Example)

```
$ find env
env/RAILS_ENV
env/LANG
```

```
$ cat env/RAILS_ENV
production
$ cat env/LANG
en_US.UTF-8
```

which are equivalent with `evn RAILS_ENV=production LANG=en_US.UTF-8` in shell.

Please note that environment variables are updated on restarting, which means deleted files are not affected.

## See Also

* [「Server::Starterに対応するとはどういうことか」の補足](http://blog.livedoor.jp/sonots/archives/40248661.html) (Japanese)
* [Server::Starter で Unicorn を起動する場合の Slow Restart](http://blog.livedoor.jp/sonots/archives/42826057.html) (Japanese)
* [Server::Starter を使って複数の Fluentd で１つのポートを待ち受ける](http://blog.livedoor.jp/sonots/archives/43219930.html) (Japanese)

## ChangeLog

See [CHANGELOG.md](CHANGELOG.md) for details.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new [Pull Request](../../pull/new/master)

## Copyright

Copyright (c) 2015 Naotoshi Seo. See [LICENSE](LICENSE) for details.

