#!/usr/bin/ruby

require 'optparse'
require_relative '../lib/server/starter'

opts = {
  :port => [],
  :path => [],
  :interval => 1,
}
OptionParser.new do |opt|
  opt.on(
    '--port=(port|host:port),(port|host:port),...',
    'TCP port to listen to (if omitted, will not bind to any ports)',
    Array
  ) {|v| opts[:port] = v }
  opt.on(
    '--path=path,path,...',
    'path at where to listen using unix socket (optional)',
    Array,
  ) {|v| opts[:path] = v }
  opt.on(
    '--dir=path',
    'working directory, start_server do chdir to before exec (optional)',
  ) {|v| opts[:dir] = v }
  opt.on(
    '--interval=seconds',
    'minimum interval to respawn the server program (default: 1)',
  ) {|v| opts[:interval] = v.to_i }
  opt.on(
    '--signal-on-hup=SIGNAL',
    'name of the signal to be sent to the server process when start_server receives a SIGHUP (default: SIGTERM). If you use this option, be sure to also use `--signal-on-term` below.',
  ) {|v| opts[:signal_on_hup] = v }
  opt.on(
    '--signal-on-term=SIGNAL',
    'name of the signal to be sent to the server process when start_server receives a SIGTERM (default: SIGTERM)',
  ) {|v| opts[:signal_on_term] = v }
  opt.on(
    '--pid-file=filename',
    'if set, writes the process id of the start_server process to the file',
  ) {|v| opts[:pid_file] = v }
  opt.on(
    '--status-file=filename',
    'if set, writes the status of the server process(es) to the file',
  ) {|v| opts[:status_file] = v }
  opt.on(
    '--envdir=ENVDIR',
    'directory that contains environment variables to the server processes. It is intended for use with `envdir` in `daemontools`. This can be overwritten by environment variable `ENVDIR`.',
  ) {|v| opts[:envdir] = v }
  opt.on(
    '--enable-auto-restart',
    'enables automatic restart by time. This can be overwritten by environment variable `ENABLE_AUTO_RESTART`.',
  ) {|v| opts[:enable_auto_restart] = v }
  opt.on(
    '--auto-restart-interval=seconds',
    'automatic restart interval (default 360). It is used with `--enable-auto-restart` option. This can be overwritten by environment variable `AUTO_RESTART_INTERVAL`.',
  ) {|v| opts[:auto_restart_interval] = v.to_i }
  opt.on(
    '--kill-old-delay=seconds',
    'time to suspend to send a signal to the old worker. The default value is 5 when `--enable-auto-restart` is set, 0 otherwise. This can be overwritten by environment variable `KILL_OLD_DELAY`.'
  ) {|v| opts[:kill_old_delay] = v.to_i }
  opt.on(
    '--restart',
    'this is a wrapper command that reads the pid of the start_server process from --pid-file, sends SIGHUP to the process and waits until the server(s) of the older generation(s) die by monitoring the contents of the --status-file'
  ) {|v| opts[:restart] = v }
  opt.on(
    '--backlog=num',
    'specifies a listen backlog parameter, whose default is SOMAXCONN (usually 128 on Linux). While SOMAXCONN is enough for most loads, large backlog is required for heavy loads.',
  ) {|v| opts[:backlog] = v.to_i }
  opt.on(
    '--version',
    'print version',
  ) {|v| puts Server::Starter::VERSION; exit 0 }
  
  opt.parse!(ARGV)
end

starter = Server::Starter.new

if opts[:restart]
  starter.restart_server(opts)
  exit 0;
end

# validate options
if ARGV.empty?
  $stderr.puts "server program not specified"
  exit 1
end

starter.start_server(opts.merge({:exec => ARGV}))

__END__
#! /usr/bin/perl

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;
use Server::Starter qw(start_server restart_server);

my %opts = (
    port => [],
    path => [],
);

GetOptions(
    map {
        $_ => do {
            my $name = (split '=', $_, 2)[0];
            $name =~ s/-/_/g;
            $opts{$name} ||= undef;
            ref($opts{$name}) ? $opts{$name} : \$opts{$name};
        },
    } qw(port=s path=s interval=i log-file=s pid-file=s dir=s signal-on-hup=s signal-on-term=s
         backlog=i envdir=s enable-auto-restart=i auto-restart-interval=i kill-old-delay=i
         status-file=s restart help version),
) or exit 1;
pod2usage(
    -exitval => 0,
    -verbose => 1,
) if $opts{help};
if ($opts{version}) {
    print "$Server::Starter::VERSION\n";
    exit 0;
}

if ($opts{restart}) {
    restart_server(%opts);
    exit 0;
}

# validate options
die "server program not specified\n"
    unless @ARGV;

start_server(
    %opts,
    exec => \@ARGV,
);
__END__

#! /usr/bin/perl

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;
use Server::Starter qw(start_server restart_server);

my %opts = (
    port => [],
    path => [],
);

GetOptions(
    map {
        $_ => do {
            my $name = (split '=', $_, 2)[0];
            $name =~ s/-/_/g;
            $opts{$name} ||= undef;
            ref($opts{$name}) ? $opts{$name} : \$opts{$name};
        },
    } qw(port=s path=s interval=i log-file=s pid-file=s dir=s signal-on-hup=s signal-on-term=s
         backlog=i envdir=s enable-auto-restart=i auto-restart-interval=i kill-old-delay=i
         status-file=s restart help version),
) or exit 1;
pod2usage(
    -exitval => 0,
    -verbose => 1,
) if $opts{help};
if ($opts{version}) {
    print "$Server::Starter::VERSION\n";
    exit 0;
}

if ($opts{restart}) {
    restart_server(%opts);
    exit 0;
}

# validate options
die "server program not specified\n"
    unless @ARGV;

start_server(
    %opts,
    exec => \@ARGV,
);

__END__

=head1 NAME

start_server - a superdaemon for hot-deploying server programs

=head1 SYNOPSIS

  start_server [options] -- server-prog server-arg1 server-arg2 ...

  # start Plack using Starlet listening at TCP port 8000
  start_server --port=8000 -- plackup -s Starlet --max-workers=100 index.psgi

=head1 DESCRIPTION

This script is a frontend of L<Server::Starter>.  For more information please refer to the documentation of the module.

=head1 OPTIONS

=head2 --port=(port|host:port)

TCP port to listen to (if omitted, will not bind to any ports)

=head2 --path=path

path at where to listen using unix socket (optional)

=head2 --dir=path

working directory, start_server do chdir to before exec (optional)

=head2 --interval=seconds

minimum interval to respawn the server program (default: 1)

=head2 --signal-on-hup=SIGNAL

name of the signal to be sent to the server process when start_server receives a SIGHUP (default: SIGTERM). If you use this option, be sure to also use C<--signal-on-term> below.

=head2 --signal-on-term=SIGNAL

name of the signal to be sent to the server process when start_server receives a SIGTERM (default: SIGTERM)

=head2 --pid-file=filename

if set, writes the process id of the start_server process to the file

=head2 --status-file=filename

if set, writes the status of the server process(es) to the file

=head2 --envdir=ENVDIR

directory that contains environment variables to the server processes.
It is intended for use with C<envdir> in C<daemontools>.
This can be overwritten by environment variable C<ENVDIR>.

=head2 --enable-auto-restart

enables automatic restart by time.
This can be overwritten by environment variable C<ENABLE_AUTO_RESTART>.

=head2 --auto-restart-interval=seconds

automatic restart interval (default 360). It is used with C<--enable-auto-restart> option.
This can be overwritten by environment variable C<AUTO_RESTART_INTERVAL>.

=head2 --kill-old-delay=seconds

time to suspend to send a signal to the old worker. The default value is 5 when C<--enable-auto-restart> is set, 0 otherwise.
This can be overwritten by environment variable C<KILL_OLD_DELAY>.

=head2 --restart

this is a wrapper command that reads the pid of the start_server process from --pid-file, sends SIGHUP to the process and waits until the server(s) of the older generation(s) die by monitoring the contents of the --status-file

=head2 --backlog
specifies a listen backlog parameter, whose default is SOMAXCONN (usually 128 on Linux). While SOMAXCONN is enough for most loads, large backlog is required for heavy loads.

=head2 --help

prints this help

=head2 --version

prints the version number

=head1 AUTHOR

Kazuho Oku

=head1 SEE ALSO

L<Server::Starter>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut
