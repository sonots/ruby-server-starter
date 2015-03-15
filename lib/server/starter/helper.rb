class Server
  class Starter
    module Helper
      def warn(msg)
        $stderr.puts msg
      end

      def croak(msg)
        $stderr.puts msg
        exit 1
      end

      def die(*args)
        if args.size == 2
          e, msg = args[0], args[1]
          $stderr.puts "#{msg}:#{e.class} #{e.message}"
        else
          msg = args[0]
          $stderr.puts msg
        end
        exit 1
      end

      def with_local_env(local_env, &block)
        orig_env = ENV.to_hash
        ENV.update(local_env)
        yield
      ensure
        ENV.replace(orig_env)
      end

      def bundler_with_clean_env(&block)
        if defined?(Bundler)
          begin
            # Bundler.with_clean_env resets ENV to initial env on loading ruby
            orig_env = ENV.to_hash
            ENV.delete_if { |k,_| k[0,7] == 'BUNDLE_' }
            if ENV.has_key? 'RUBYOPT'
              ENV['RUBYOPT'] = ENV['RUBYOPT'].sub '-rbundler/setup', ''
            end
            %w[RUBYLIB GEM_HOME].each {|key| ENV.delete(key) }
            yield
          ensure
            ENV.replace(orig_env)
          end
        else
          yield
        end
      end
    end
  end
end
