#!/usr/bin/ruby

require 'server/starter/puma_listener'
listener = ::Server::Starter::PumaListener

unless listener.listen # Configure PUMA_INHERIT_\d NEV
  $stderr.puts "[ERROR] Not running under server starter"
  exit 1
end

args = ARGV.dup
args << { :close_others => false }
Kernel.exec(*args)
