#!/usr/bin/env ruby
require 'rack'

Rack::Server.new.instance_exec do
  @options.update({
    Host: '127.0.0.1',
    Port: 8694,
  })
  self
end.start
