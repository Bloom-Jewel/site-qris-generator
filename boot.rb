#!/usr/bin/env ruby
require 'rack'

Rack::Server.new.instance_exec do
  @options.update({
    Host: '0.0.0.0',
    Port: 8694,
  })
  if options[:environment] == 'development' then
    $stderr.puts 'Do not use development env!'
    @options[:environment] = 'deployment'
  end
  self
end.start
