#!/usr/bin/ruby

if ENV.key?('SERVER_STARTER_PORT')
  ENV['SERVER_STARTER_PORT'].split(';').each.with_index do |x, i|
    path_or_port, fd = x.split('=', 2)
    if path_or_port.match(/(?:^|:)\d+$/)
      url = "tcp://#{path_or_port}"
    else
      url = "unix://#{path_or_port}"
    end
    ENV["PUMA_INHERIT_#{i}"] = "#{fd}:#{url}"
  end
end

args = ARGV.dup
args << { :close_others => false }
Kernel.exec(*args)
