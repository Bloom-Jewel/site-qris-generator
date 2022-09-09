#\ -p 8704
require 'bundler'
Bundler.require(:default, :default)
require_relative 'qris'

use Rack::Reloader, 0
run QRISConverter::Application.new
