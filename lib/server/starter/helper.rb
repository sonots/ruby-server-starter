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

      def die(msg)
        if $!
          $stderr.puts "#{msg}:#{$!.class} #{$!.message}"
        else
          $stderr.puts msg
        end
        exit 1
      end

      def with_local_env(local_env, &block)
        orig_env = local_env.keys.map {|k| [k, ENV[k]] }.to_h
        ENV.update(local_env)
        yield
      ensure
        ENV.update(orig_env)
      end

      # A small tweaked version of Bundler.with_clean_env
      #
      # Bundler has Bundler.with_clean_env by its own, but the method
      # replace ENV with ENV captured on starting.
      # cf. https://github.com/bundler/bundler/blob/e8c962ef2a3215cdc6fd411b6724f091a16793d6/lib/bundler.rb#L230
      # Server::Starter changes ENV during running to communicate
      # with child processes, so we need to keep the changed ENV.
      # This is why I needed this small tweaked version
      def bundler_with_clean_env(&block)
        if defined?(Bundler)
          begin
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
