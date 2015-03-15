require 'socket'
require 'fcntl'
require 'timeout'
require 'server/starter/version'
require 'server/starter/helper'

class Server::Starter
  include Helper

  def initialize
    @signals_received  = []
    @current_worker    = nil
    @old_workers       = {}
    @last_restart_time = []
  end

  def start_server(opts)
    # symbolize keys
    opts = opts.map {|k, v| [k.to_sym, v] }.to_h
    opts[:interval] ||= 1
    opts[:signal_on_hup]  ||= 'TERM'
    opts[:signal_on_term] ||= 'TERM'
    opts[:backlog] ||= Socket::SOMAXCONN
    [:signal_on_hup, :signal_on_term].each do |key|
      # normalize to the one that can be passed to kill
      opts[key].tr!("a-z", "A-Z")
      opts[key].sub!(/^SIG/i, "")
    end

    # prepare args
    ports = Array(opts[:port])
    paths = Array(opts[:path])
    unless ports.empty? || paths.empty?
      croak "either of ``port'' or ``path'' option is andatory"
    end
    unless opts[:exec] && opts[:exec].is_a?(Array)
      croak "mandatory option ``exec'' is missing or not an array"
    end

    # set envs
    ENV['ENVDIR'] = opts[:envdir] if opts[:envdir]
    ENV['ENABLE_AUTO_RESTART'] = opts[:enable_auto_restart] ? '1' : nil
    ENV['KILL_OLD_DELAY'] = opts[:kill_old_delay].to_s if opts[:kill_old_delay]
    ENV['AUTO_RESTART_INTERVAL'] = opts[:auto_restart_interval].to_s if opts[:auto_restart_interval]

    # open pid file
    if opts[:pid_file]
      File.open(opts[:pid_file], "w") do |fh|
        fh.puts $$
      end rescue die $!, "failed to open file:#{opts[:pid_file]}"
      at_exit { File.unlink opts[:pid_file] rescue nil }
    end

    # open log file
    if opts[:log_file]
      File.open(opts[:log_file], "a") do |fh|
        $stdout.flush
        $stderr.flush
        $stdout.reopen(fh) rescue die $!, "failed to reopen STDOUT to file"
        $stderr.reopen(fh) rescue die $!, "failed to reopen STDERR to file"
      end
    end

    # create guard that removes the status file
    if opts[:status_file]
      at_exit { File.unlink opts[:status_file] rescue nil }
    end

    $stderr.puts "start_server (pid:#{$$}) starting now..."

    # start listening, setup envvar
    socks = []
    sockenvs = []
    ports.each do |port|
      sock = nil
      begin
        if port =~ /^\s*(\d+)\s*$/
          # sock = Socket.new(:INET, :STREAM)
          # addr = Socket.pack_sockaddr_in(port, '0.0.0.0')
          # sock.setsockopt(:SOCKET, :REUSEADDR, true)
          # sock.bind(addr)
          # sock.listen(opts[:backlog])
          sock = TCPServer.new("0.0.0.0", port)
          sock.setsockopt(:SOCKET, :REUSEADDR, true)
          sock.listen(opts[:backlog])
        elsif port =~ /^\s*(.*)\s*:\s*(\d+)\s*$/
          _bind, _port = $1, $2
          sock = TCPServer.new(_bind, _port)
          sock.setsockopt(:SOCKET, :REUSEADDR, true)
          sock.listen(opts[:backlog])
        else
          croak "invalid ``port'' value:#{port}"
        end
      rescue
        die $!, "failed to listen to port"
      end
      sock.fcntl(Fcntl::F_SETFD, 0) rescue die $!, "fcntl(F_SETFD, 0) failed"
      sockenvs.push "#{port}=#{sock.fileno}"
      socks.push sock
    end

    at_exit {
      paths.each do |path|
        File.symlink?(path) and File.unlink(path) rescue nil
      end
    }
    paths.each do |path|
      if File.symlink?(path)
        warn "removing existing socket file:#{path}"
        File.unlink(path) rescue die $!, "failed to remove existing socket file:#{path}"
      end
      File.unlink(path) rescue nil
      saved_umask = File.umask(0)
      begin
        sock = UNIXServer.new(path)
        sock.listen(opts[:backlog])
      rescue
        die $!, "failed to listen to file #{path}"
      end
      sock.fcntl(Fcntl::F_SETFD, 0) rescue die $!, "fcntl(F_SETFD, 0) failed"
      sockenvs.push "path=#{sock.fileno}"
      socks.push sock
    end
    ENV['SERVER_STARTER_PORT'] = sockenvs.join(";")
    ENV['SERVER_STARTER_GENERATION'] = "0"

    # setup signal handlers
    %w(INT TERM HUP ALRM).each do |signal|
      Signal.trap(signal) {
        @signals_received.push(signal)
        @signal_wait_thread.kill if @signal_wait_thread
      }
    end
    Signal.trap('PIPE') { 'IGNORE' }

    # setup status monitor
    update_status =
      if opts[:status_file]
        Proc.new {
          tmpfn = "#{opts[:status_file]}.#{$$}"
          File.open(tmpfn, "w") do |tmpfh|
            gen_pids = @current_worker ?
              {ENV['SERVER_STARTER_GENERATION'] => @current_worker} :
              {}
            @old_workers.each {|pid, gen| gen_pids[gen] = pid }
            gen_pids.keys.map(&:to_i).sort.each {|gen| tmpfh.puts "#{gen}:#{gen_pids[gen.to_s]}" }
          end rescue die $!, "failed to create temporary file:#{tmpfn}"
          begin
            File.rename(tmpfn, opts[:status_file])
          rescue
            die $!, "failed to rename #{tmpfn} to #{opts[:status_file]}"
          end
        }
      else
        Proc.new {}
      end

    # setup the start_worker function
    start_worker = Proc.new {
      pid = nil
      while true
        ENV['SERVER_STARTER_GENERATION'] = (ENV['SERVER_STARTER_GENERATION'].to_i + 1).to_s
        begin
          pid = fork
        rescue
          die $!, "fork(2) failed"
        end
        if pid.nil? # child process
          args = Array(opts[:exec]).dup
          if opts[:dir]
            Dir.chdir opts[:dir] rescue die $1, "failed to chdir"
          end
          begin
            bundler_with_clean_env do
              args << {:close_others => false}
              exec(*args)
            end
          rescue
            $stderr.puts "failed to exec #{args[0]}:#{$!.class} #{$!.message}"
            exit(255)
          end
        end
        $stderr.puts "starting new worker #{pid}"
        sleep opts[:interval]
        break if (@signals_received - [:HUP]).size > 0
        break if Process.waitpid(pid, Process::WNOHANG).nil?
        $stderr.puts "new worker #{pid} seems to have failed to start, exit status:#{$?.exitstatus}"
      end
      # ready, update the environment
      @current_worker = pid
      @last_restart_time = Time.now
      update_status.call
    }

    # setup the wait function
    wait = Proc.new {
      flags = @signals_received.empty? ? 0 : Process::WNOHANG
      r = nil
      # waitpid can not get EINTR on receiving signal, so create a thread,
      # and kill the thread on receiving signal to exit blocking
      #
      # there is another way to use wait3 which raises EINTR on receiving signal,
      # but proc-wait3 gem requires gcc, etc to compile its C codes.
      #
      #     require 'proc/wait3'
      #     begin
      #       rusage = Process.wait3(flags)
      #       r = [rusage.pid, rusage.status] if rusage
      #     rescue Errno::EINTR
      #       sleep 0.1 # need to wait until Signal.trap finishes its operation, terrible
      #       nil
      #     end
      @signal_wait_thread = Thread.start do
        if flags != 0 && ENV['ENABLE_AUTO_RESTART']
          begin
            timeout(1) do
              pid = Process.waitpid(-1, flags)
              r = [pid, $?.exitstatus] if pid
            end
          rescue Timeout::Error
            # Process.kill('ALRM', Process.pid)
            Thread.exit
          end
        else
          pid = Process.waitpid(-1, flags)
          r = [pid, $?.exitstatus] if pid
        end
      end
      @signal_wait_thread.join
      @signal_wait_thread = nil
      r
    }

    # setup the cleanup function
    cleanup = Proc.new {|sig|
      term_signal = sig == 'TERM' ? opts[:signal_on_term] : 'TERM'
      @old_workers[@current_worker] = ENV['SERVER_STARTER_GENERATION']
      @current_worker = nil
      $stderr.print "received #{sig}, sending #{term_signal} to all workers:",
        @old_workers.keys.sort.join(','), "\n"
      @old_workers.keys.sort.each {|pid| Process.kill(term_signal, pid) }
      while true
        died_worker = Process.waitpid(-1, Process::WNOHANG)
        if died_worker
          $stderr.puts "worker #{died_worker} died, status:#{$?.exitstatus}"
          @old_workers.delete(died_worker)
          update_status.call
          break if @old_workers.empty?
        end
      end
      $stderr.puts "exiting"
    }

    # the main loop
    start_worker.call
    while true
      # wait for next signal (or when auto-restart becomes necessary)
      r = wait.call
      # reload env if necessary
      loaded_env = _reload_env
      ENV['AUTO_RESTART_INTERVAL'] ||= "360" if ENV['ENABLE_AUTO_RESTART']
      with_local_env(loaded_env) do
        # restart if worker died
        if r
          died_worker, status = r
          if died_worker == @current_worker
            $stderr.puts "worker #{died_worker} died unexpectedly with status:#{status}, restarting"
            start_worker.call
          else
            $stderr.puts "old worker #{died_worker} died, status:#{status}"
            @old_workers.delete(died_worker)
            update_status.call
          end
        end
        # handle signals
        restart = nil
        while !@signals_received.empty?
          sig = @signals_received.shift
          if sig == 'HUP'
            $stderr.puts "received HUP, spawning a new worker"
            restart = true
            break
          elsif sig == 'ALRM'
            # skip
          else
            return cleanup.call(sig)
          end
        end
        if !restart && ENV['ENABLE_AUTO_RESTART']
          auto_restart_interval = ENV['AUTO_RESTART_INTERVAL'].to_i
          elapsed_since_restart = Time.now - @last_restart_time
          if elapsed_since_restart >= auto_restart_interval && @old_workers.empty?
            $stderr.puts "autorestart triggered (interval=#{auto_restart_interval})"
            restart = true
          elsif elapsed_since_restart >= auto_restart_interval * 2
            $stderr.puts "autorestart triggered (forced, interval=#{auto_restart_interval})"
            restart = true
          end
        end
        # restart if requested
        if restart
          @old_workers[@current_worker] = ENV['SERVER_STARTER_GENERATION']
          start_worker.call
          $stderr.print "new worker is now running, sending #{opts[:signal_on_hup]} to old workers:"
          if !@old_workers.empty?
            $stderr.puts @old_workers.keys.sort.join(',')
          else
            $stderr.puts "none"
          end
          kill_old_delay = ENV['KILL_OLD_DELAY'] ? ENV['KILL_OLD_DELAY'].to_i : ENV['ENABLE_AUTO_RESTART'] ? 5 : 0
          if kill_old_delay != 0
            $stderr.puts "sleeping #{kill_old_delay} secs before killing old workers"
            sleep kill_old_delay
          end
          $stderr.puts "killing old workers"
          @old_workers.keys.sort {|pid| Process.kill(opts[:signal_on_hup], pid) }
        end
      end
    end

    die "unreachable"
  end

  def restart_server(opts)
    unless opts[:pid_file] && opts[:status_file]
      die "--restart option requires --pid-file and --status-file to be set as well"
    end

    # get first pid
    pid = Proc.new {
      begin
        File.open(opts[:pid_file]) do |fd|
          line = fd.gets
          line.chomp
        end
      rescue
        die $!, "failed to open file:#{opts[:pid_file]}"
      end
    }.call

    # function that returns a list of active generations in sorted order
    get_generations = Proc.new {
      begin
        File.readlines(opts[:status_file]).map do |line|
          line =~ /^(\d+):/ ? $1 : nil
        end.compact.map(&:to_i).sort.uniq
      rescue
        die $!, "failed to open file:#{opts[:status_file]}"
      end
    }

    # wait for this generation
    wait_for = Proc.new {
      gens = get_generations.call
      die "no active process found in the status file" if gens.empty?
      gens.last.to_i + 1
    }.call

    # send HUP
    Process.kill('HUP', pid.to_i) rescue die $!, "failed to send SIGHUP to the server process"

    # wait for the generation
    while true
      gens = get_generations.call
      break if gens.size == 1 && gens[0].to_i == wait_for.to_i
      sleep 1
    end
  end

  def server_ports
    die "no environment variable SERVER_STARTER_PORT. Did you start the process using server_starter?" unless ENV['SERVER_STARTER_PORT']
    ENV['SERVER_STARTER_PORT'].split(';').map do |_|
      _.split('=', 2)
    end.to_h
  end

  def _reload_env
    dn = ENV['ENVDIR']
    return {} if dn.nil? or !File.exist?(dn)
    env = {}
    Dir.open(dn) do |d|
      while n = d.read
        next if n =~ /^\./
        File.open("#{dn}/#{n}") do |fh|
          first_line = fh.gets.chomp
          env[n] = first_line if first_line
        end
      end
    end
    env
  end
end

__END__

package Server::Starter;

use 5.008;
use strict;
use warnings;
use Carp;
use Fcntl;
use IO::Handle;
use IO::Socket::INET;
use IO::Socket::UNIX;
use List::MoreUtils qw(uniq);
use POSIX qw(:sys_wait_h);
use Proc::Wait3;
use Scope::Guard;

use Exporter qw(import);

our $VERSION = '0.19';
our @EXPORT_OK = qw(start_server restart_server server_ports);

my @signals_received;

sub start_server {
    my $opts = {
        (@_ == 1 ? @$_[0] : @_),
    };
    $opts->{interval} = 1
        if not defined $opts->{interval};
    $opts->{signal_on_hup}  ||= 'TERM';
    $opts->{signal_on_term} ||= 'TERM';
    $opts->{backlog} ||= Socket::SOMAXCONN();
    for ($opts->{signal_on_hup}, $opts->{signal_on_term}) {
        # normalize to the one that can be passed to kill
        tr/a-z/A-Z/;
        s/^SIG//i;
    }

    # prepare args
    my $ports = $opts->{port};
    my $paths = $opts->{path};
    croak "either of ``port'' or ``path'' option is mandatory\n"
        unless $ports || $paths;
    $ports = [ $ports ]
        if ! ref $ports && defined $ports;
    $paths = [ $paths ]
        if ! ref $paths && defined $paths;
    croak "mandatory option ``exec'' is missing or is not an arrayref\n"
        unless $opts->{exec} && ref $opts->{exec} eq 'ARRAY';

    # set envs
    $ENV{ENVDIR} = $opts->{envdir}
        if defined $opts->{envdir};
    $ENV{ENABLE_AUTO_RESTART} = $opts->{enable_auto_restart}
        if defined $opts->{enable_auto_restart};
    $ENV{KILL_OLD_DELAY} = $opts->{kill_old_delay}
        if defined $opts->{kill_old_delay};
    $ENV{AUTO_RESTART_INTERVAL} = $opts->{auto_restart_interval}
        if defined $opts->{auto_restart_interval};

    # open pid file
    my $pid_file_guard = sub {
        return unless $opts->{pid_file};
        open my $fh, '>', $opts->{pid_file}
            or die "failed to open file:$opts->{pid_file}: $!";
        print $fh "$$\n";
        close $fh;
        return Scope::Guard->new(
            sub {
                unlink $opts->{pid_file};
            },
        );
    }->();
    
    # open log file
    if ($opts->{log_file}) {
        open my $fh, '>>', $opts->{log_file}
            or die "failed to open log file:$opts->{log_file}: $!";
        STDOUT->flush;
        STDERR->flush;
        open STDOUT, '>&', $fh
            or die "failed to dup STDOUT to file: $!";
        open STDERR, '>&', $fh
            or die "failed to dup STDERR to file: $!";
        close $fh;
    }
    
    # create guard that removes the status file
    my $status_file_guard = $opts->{status_file} && Scope::Guard->new(
        sub {
            unlink $opts->{status_file};
        },
    );
    
    print STDERR "start_server (pid:$$) starting now...\n";
    
    # start listening, setup envvar
    my @sock;
    my @sockenv;
    for my $port (@$ports) {
        my $sock;
        if ($port =~ /^\s*(\d+)\s*$/) {
            $sock = IO::Socket::INET->new(
                Listen    => $opts->{backlog},
                LocalPort => $port,
                Proto     => 'tcp',
                ReuseAddr => 1,
            );
        } elsif ($port =~ /^\s*(.*)\s*:\s*(\d+)\s*$/) {
            $port = "$1:$2";
            $sock = IO::Socket::INET->new(
                Listen    => $opts->{backlog},
                LocalAddr => $port,
                Proto     => 'tcp',
                ReuseAddr => 1,
            );
        } else {
            croak "invalid ``port'' value:$port\n"
        }
        die "failed to listen to $port:$!"
            unless $sock;
        fcntl($sock, F_SETFD, my $flags = '')
                or die "fcntl(F_SETFD, 0) failed:$!";
        push @sockenv, "$port=" . $sock->fileno;
        push @sock, $sock;
    }
    my $path_remove_guard = Scope::Guard->new(
        sub {
            -S $_ and unlink $_
                for @$paths;
        },
    );
    for my $path (@$paths) {
        if (-S $path) {
            warn "removing existing socket file:$path";
            unlink $path
                or die "failed to remove existing socket file:$path:$!";
        }
        unlink $path;
        my $saved_umask = umask(0);
        my $sock = IO::Socket::UNIX->new(
            Listen => $opts->{backlog},
            Local  => $path,
        ) or die "failed to listen to file $path:$!";
        umask($saved_umask);
        fcntl($sock, F_SETFD, my $flags = '')
            or die "fcntl(F_SETFD, 0) failed:$!";
        push @sockenv, "$path=" . $sock->fileno;
        push @sock, $sock;
    }
    $ENV{SERVER_STARTER_PORT} = join ";", @sockenv;
    $ENV{SERVER_STARTER_GENERATION} = 0;
    
    # setup signal handlers
    $SIG{$_} = sub {
        push @signals_received, $_[0];
    } for (qw/INT TERM HUP ALRM/);
    $SIG{PIPE} = 'IGNORE';
    
    # setup status monitor
    my ($current_worker, %old_workers, $last_restart_time);
    my $update_status = $opts->{status_file}
        ? sub {
            my $tmpfn = "$opts->{status_file}.$$";
            open my $tmpfh, '>', $tmpfn
                or die "failed to create temporary file:$tmpfn:$!";
            my %gen_pid = (
                ($current_worker
                 ? ($ENV{SERVER_STARTER_GENERATION} => $current_worker)
                 : ()),
                map { $old_workers{$_} => $_ } keys %old_workers,
            );
            print $tmpfh "$_:$gen_pid{$_}\n"
                for sort keys %gen_pid;
            close $tmpfh;
            rename $tmpfn, $opts->{status_file}
                or die "failed to rename $tmpfn to $opts->{status_file}:$!";
        } : sub {
        };

    # setup the start_worker function
    my $start_worker = sub {
        my $pid;
        while (1) {
            $ENV{SERVER_STARTER_GENERATION}++;
            $pid = fork;
            die "fork(2) failed:$!"
                unless defined $pid;
            if ($pid == 0) {
                my @args = @{$opts->{exec}};
                # child process
                if (defined $opts->{dir}) {
                    chdir $opts->{dir} or die "failed to chdir:$!";
                }
                { exec { $args[0] } @args };
                print STDERR "failed to exec $args[0]$!";
                exit(255);
            }
            print STDERR "starting new worker $pid\n";
            sleep $opts->{interval};
            if ((grep { $_ ne 'HUP' } @signals_received)
                    || waitpid($pid, WNOHANG) <= 0) {
                last;
            }
            print STDERR "new worker $pid seems to have failed to start, exit status:$?\n";
        }
        # ready, update the environment
        $current_worker = $pid;
        $last_restart_time = time;
        $update_status->();
    };

    # setup the wait function
    my $wait = sub {
        my $block = @signals_received == 0;
        my @r;
        if ($block && $ENV{ENABLE_AUTO_RESTART}) {
            alarm(1);
            @r = wait3($block);
            alarm(0);
        } else {
            @r = wait3($block);
        }
        return @r;
    };

    # setup the cleanup function
    my $cleanup = sub {
        my $sig = shift;
        my $term_signal = $sig eq 'TERM' ? $opts->{signal_on_term} : 'TERM';
        $old_workers{$current_worker} = $ENV{SERVER_STARTER_GENERATION};
        undef $current_worker;
        print STDERR "received $sig, sending $term_signal to all workers:",
            join(',', sort keys %old_workers), "\n";
        kill $term_signal, $_
            for sort keys %old_workers;
        while (%old_workers) {
            if (my @r = wait3(1)) {
                my ($died_worker, $status) = @r;
                print STDERR "worker $died_worker died, status:$status\n";
                delete $old_workers{$died_worker};
                $update_status->();
            }
        }
        print STDERR "exiting\n";
    };

    # the main loop
    $start_worker->();
    while (1) {
        # wait for next signal (or when auto-restart becomes necessary)
        my @r = $wait->();
        # reload env if necessary
        my %loaded_env = _reload_env();
        my @loaded_env_keys = keys %loaded_env;
        local @ENV{@loaded_env_keys} = map { $loaded_env{$_} } (@loaded_env_keys);
        $ENV{AUTO_RESTART_INTERVAL} ||= 360
            if $ENV{ENABLE_AUTO_RESTART};
        # restart if worker died
        if (@r) {
            my ($died_worker, $status) = @r;
            if ($died_worker == $current_worker) {
                print STDERR "worker $died_worker died unexpectedly with status:$status, restarting\n";
                $start_worker->();
            } else {
                print STDERR "old worker $died_worker died, status:$status\n";
                delete $old_workers{$died_worker};
                $update_status->();
            }
        }
        # handle signals
        my $restart;
        while (@signals_received) {
            my $sig = shift @signals_received;
            if ($sig eq 'HUP') {
                print STDERR "received HUP, spawning a new worker\n";
                $restart = 1;
                last;
            } elsif ($sig eq 'ALRM') {
                # skip
            } else {
                return $cleanup->($sig);
            }
        }
        if (! $restart && $ENV{ENABLE_AUTO_RESTART}) {
            my $auto_restart_interval = $ENV{AUTO_RESTART_INTERVAL};
            my $elapsed_since_restart = time - $last_restart_time;
            if ($elapsed_since_restart >= $auto_restart_interval && ! %old_workers) {
                print STDERR "autorestart triggered (interval=$auto_restart_interval)\n";
                $restart = 1;
            } elsif ($elapsed_since_restart >= $auto_restart_interval * 2) {
                print STDERR "autorestart triggered (forced, interval=$auto_restart_interval)\n";
                $restart = 1;
            }
        }
        # restart if requested
        if ($restart) {
            $old_workers{$current_worker} = $ENV{SERVER_STARTER_GENERATION};
            $start_worker->();
            print STDERR "new worker is now running, sending $opts->{signal_on_hup} to old workers:";
            if (%old_workers) {
                print STDERR join(',', sort keys %old_workers), "\n";
            } else {
                print STDERR "none\n";
            }
            my $kill_old_delay = defined $ENV{KILL_OLD_DELAY} ? $ENV{KILL_OLD_DELAY} : $ENV{ENABLE_AUTO_RESTART} ? 5 : 0;
            if ($kill_old_delay != 0) {
                print STDERR "sleeping $kill_old_delay secs before killing old workers\n";
                sleep $kill_old_delay;
            }
            print STDERR "killing old workers\n";
            kill $opts->{signal_on_hup}, $_
                for sort keys %old_workers;
        }
    }

    die "unreachable";
}

sub restart_server {
    my $opts = {
        (@_ == 1 ? @$_[0] : @_),
    };
    die "--restart option requires --pid-file and --status-file to be set as well\n"
        unless $opts->{pid_file} && $opts->{status_file};
    
    # get pid
    my $pid = do {
        open my $fh, '<', $opts->{pid_file}
            or die "failed to open file:$opts->{pid_file}:$!";
        my $line = <$fh>;
        chomp $line;
        $line;
    };
    
    # function that returns a list of active generations in sorted order
    my $get_generations = sub {
        open my $fh, '<', $opts->{status_file}
            or die "failed to open file:$opts->{status_file}:$!";
        uniq sort { $a <=> $b } map { /^(\d+):/ ? ($1) : () } <$fh>;
    };
    
    # wait for this generation
    my $wait_for = do {
        my @gens = $get_generations->()
            or die "no active process found in the status file";
        pop(@gens) + 1;
    };
    
    # send HUP
    kill 'HUP', $pid
        or die "failed to send SIGHUP to the server process:$!";
    
    # wait for the generation
    while (1) {
        my @gens = $get_generations->();
        last if scalar(@gens) == 1 && $gens[0] == $wait_for;
        sleep 1;
    }
}

sub server_ports {
    die "no environment variable SERVER_STARTER_PORT. Did you start the process using server_starter?",
        unless $ENV{SERVER_STARTER_PORT};
    my %ports = map {
        +(split /=/, $_, 2)
    } split /;/, $ENV{SERVER_STARTER_PORT};
    \%ports;
}

sub _reload_env {
    my $dn = $ENV{ENVDIR};
    return if !defined $dn or !-d $dn;
    my $d;
    opendir($d, $dn) or return;
    my %env;
    while (my $n = readdir($d)) {
        next if $n =~ /^\./;
        open my $fh, '<', "$dn/$n" or next;
        chomp(my $v = <$fh>);
        $env{$n} = $v if defined $v;
    }
    return %env;
}

1;
__END__

=head1 NAME

Server::Starter - a superdaemon for hot-deploying server programs

=head1 SYNOPSIS

  # from command line
  % start_server --port=80 my_httpd

  # in my_httpd
  use Server::Starter qw(server_ports);

  my $listen_sock = IO::Socket::INET->new(
      Proto => 'tcp',
  );
  $listen_sock->fdopen((values %{server_ports()})[0], 'w')
      or die "failed to bind to listening socket:$!";

  while (1) {
      if (my $conn = $listen_sock->accept) {
          ....
      }
  }

=head1 DESCRIPTION

It is often a pain to write a server program that supports graceful restarts, with no resource leaks.  L<Server::Starter> solves the problem by splitting the task into two.  One is L<start_server>, a script provided as a part of the module, which works as a superdaemon that binds to zero or more TCP ports or unix sockets, and repeatedly spawns the server program that actually handles the necessary tasks (for example, responding to incoming commenctions).  The spawned server programs under L<Server::Starter> call accept(2) and handle the requests.

To gracefully restart the server program, send SIGHUP to the superdaemon.  The superdaemon spawns a new server program, and if (and only if) it starts up successfully, sends SIGTERM to the old server program.

By using L<Server::Starter> it is much easier to write a hot-deployable server.  Following are the only requirements a server program to be run under L<Server::Starter> should conform to:

- receive file descriptors to listen to through an environment variable
- perform a graceful shutdown when receiving SIGTERM

A Net::Server personality that can be run under L<Server::Starter> exists under the name L<Net::Server::SS::PreFork>.

=head1 METHODS

=over 4

=item server_ports

Returns zero or more file descriptors on which the server program should call accept(2) in a hashref.  Each element of the hashref is: (host:port|port|path_of_unix_socket) => file_descriptor.

=item start_server

Starts the superdaemon.  Used by the C<start_server> script.

=back

=head1 AUTHOR

Kazuho Oku

=head1 SEE ALSO

L<Net::Server::SS::PreFork>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut
