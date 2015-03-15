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

Following is an example to run uniocorn server under ```Server::Starter```.

The command line example:

```
bundle exec start_server.rb --status-file=/path/to/app/log/unicorn.stat \
  --port=10080 --signal-on-hup=CONT --dir=/path/to/app -- \
  bundle exec --keep-file-descriptors unicorn -c config/unicorn.conf.rb config.ru
```

An example of unicorn.conf:

```ruby
worker_processes  4
preload_app true
 
APP_ROOT = File.expand_path('../..', __FILE__)
status_file = File.join(APP_ROOT, 'log/unicorn.stat')
 
if ENV.key?('SERVER_STARTER_PORT')
  fds = ENV['SERVER_STARTER_PORT'].split(';').map { |x|
    path_or_port, fd = x.split('=', 2)
    fd
  }
  ENV['UNICORN_FD'] = fds.join(',')
  ENV.delete('SERVER_STARTER_PORT')
else
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
 
  begin
    # This allows a new master process to incrementally
    # phase out the old master process with SIGTTOU to avoid a
    # thundering herd (especially in the "preload_app false" case)
    # when doing a transparent upgrade.  The last worker spawned
    # will then kill off the old master process with a SIGQUIT.
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
```

## See Also

* [「Server::Starterに対応するとはどういうことか」の補足](http://blog.livedoor.jp/sonots/archives/40248661.html) (Japanese)
* [Server::Starter で Unicorn を起動する場合の Slow Restart](http://blog.livedoor.jp/sonots/archives/42826057.html) (Japanese)

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

