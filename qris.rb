require 'json'
require 'digest'
require 'net/http'

module QRISConverter
  # load scripts from personal repository
  # @return [void]
  def self.load_local_scripts
    local_script_dir = File.join(__dir__, 'local')
    return unless File.directory? local_script_dir
    Dir.glob(File.join(local_script_dir, '**.rb')) do |file|
      require file
    end
  end
  
  # load scripts from name space
  # @return [void]
  def self.load_directory
    dir_name = File.basename(__FILE__, File.extname(__FILE__))
    Dir.glob(File.join(__dir__, dir_name, '**.rb')) do |file|
      require file
    end
  end
  
  load_local_scripts

  # @return [String] config file path
  def self.config_path
    File.join(__dir__, "config.yml")
  end
  
  # parse the config file.
  # @return [Hash] config data
  def self.config
    return unless File.exists?(self.config_path)
    @_oauthcfg ||= YAML.safe_load(File.read(self.config_path), aliases: true, symbolize_names: true).freeze
  end

  load_directory

  
  class Application
    def call(env)
      req = Rack::Request.new(env)
      handle_route(req)
    end
    def handle_route(req)
      Router.new(req).process.finish
    end
  end
end
