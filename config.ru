#\ -p 8704
require 'bundler'
Bundler.require(:default, :default)
require_relative 'qris'

Rack::Server.middleware.reject! do |mid|
  [Rack::Lint, Rack::ShowExceptions].include? mid[0]
end

use Rack::Reloader, 0
run QRISConverter::Application.new
