# frozen_string_literal: true

require 'falcon/environment/rack'

port = ENV.fetch('PORT', 3000).to_i
env = ENV.fetch('RAILS_ENV', 'development')

class Falcon::Command::Host
  def container_class
    Async::Container::Hybrid
  end
end

## NOTE (k1): Broken in async-http 0.77 through 0.79, keep checking: https://github.com/socketry/async-http/issues/183
#module FinishableBodyCloser
#  def read
#    super
#  ensure
#    @closed.value = true if @body.empty?
#  end
#end
#
#Async::HTTP::Protocol::HTTP1::Finishable.prepend(FinishableBodyCloser)

# NOTE (k1): This changes the behavior of Falcon's accept loop to not spawn Fibers until request capacity is available, preventing overload - this is similar to Puma with no request queue.
# See: https://github.com/socketry/falcon/issues/212 and https://github.com/socketry/io-endpoint/issues/14
class IO::Endpoint::Wrapper
  def accept(server, timeout: nil, linger: nil, **options, &block)
    loop do
      socket, address = server.accept
      set_timeout(socket, timeout) if timeout

      if socket.respond_to?(:start)
        begin
          socket.start
        rescue
          socket.close
          raise
        end
      end

      address ||= socket.remote_address

      puts "Calling downstream handler..."
      block.call(socket, address)
      puts "Downstream handler call yielded!"
    end
  end
end

service 'async-test' do
  include Falcon::Environment::Rack

  rackup_path File.expand_path('config.ru', File.dirname(__FILE__))

  container_options({ forks: 1, threads: 1, restart: true })

  endpoint ::Async::HTTP::Endpoint.parse("http://[::]:#{port}").with(reuse_address: true, timeout: 300)
end
