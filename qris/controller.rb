module QRISConverter
  require 'erb'
  class QROutput
    attr_accessor :lite
    attr_accessor :code
    attr_accessor :value
    attr_accessor :url
    attr_accessor :data
    attr_accessor :debug
    
    def process(template)
      template.result(binding)
    end
  end
  class Controller
    def initialize(req, resp)
      @request = req
      @response = resp
      @layout = nil
    end
    
    def load_page
      _process_input
    end
    
    def process_qrcode
      _process_input
    end

    private
    def _user_agents
      @request.user_agent.scan(/(\w+(?:\/\S+)?)(?:\s+\(([^\)]+)\))?/)
    end
    def _is_not_moz?
      !_user_agents[0][0].include? 'Mozilla'
    rescue
      true
    end
    def _process_input
      @layout = 'qris/page'
      qr = QROutput.new
      qr.lite = false
      if @request.post? then
        qr.code = @request.POST['base']
        qr.value = @request.POST['value'].to_s.empty? ? nil : sprintf("%.2f", @request.POST['value'].to_f)
        qr.url = @request.POST['mark']
      else
        qr.code = nil
        qr.value = nil
        qr.url = nil
      end
      
      unless _is_not_moz?
        qr.code = (QRISConverter.config[:qris][:emv_data] rescue nil) if qr.code.nil?
      end
      qr.lite = true if qr.code.nil?
      
      qr.data = 'about:blank'
      if qr.lite then
        qr.debug = ''
      else
        merchant = Merchant::parse_str(Merchant::EMVRoot.new, qr.code)
        merchant.static_code!
        qr.code = merchant.to_emv
        merchant.set_fee(false)
        
        new_code = qr.code
        unless qr.value.to_s.empty? then
          merchant.dynamic_code! qr.value
          new_code = merchant.to_emv
        end
        
        processor = RQRCode::QRCode.new(new_code)
        image_data = _process_image_output(
          processor.as_png(
            module_px_size: 2,
            size: 960,
          ), qr.url
        )
        qr.data = image_data.to_data_url
        qr.debug = merchant.debug_emv
      end
      template = ERB.new(File.read(File.join(Dir.pwd, 'views', @layout + '.html.erb')))
      @response.write qr.process(template)
    end
    def _process_image_output(processor, url)
      size = 960
      
      unless url.nil? then
        uri = URI(url)
        
        qr_back = ChunkyPNG::Image.new(size/5, size/5, '#ffffff')
        qr_logo = nil
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.port == 443) do |http|
          req = Net::HTTP::Get.new(uri.path)
          res = http.request req
          res.value
          qr_logo = ChunkyPNG::Image.from_string(res.body)
        rescue => e
          p e
        end
        if qr_logo then
          qr_logo.resample_nearest_neighbor! size / 5, size / 5
          processor.replace! qr_back, (size * 2 / 5), (size * 2 / 5)
          processor.compose! qr_logo, (size * 2 / 5), (size * 2 / 5)
        end
      end if false
      
      processor
    end
    def ping_redirect
      rq_ua = @request.user_agent.split(';')
      ok_ua = FastOAuth.config[:server][:allowed_ping_agents]
      ok_ua.any? do |pattern|
        rq_ua.any? do |ua| ua.include?(pattern) end
      end.tap do |result|
        fail RouteNotFound, "#{rq_ua.join(';')} not allowed to ping" unless result
        @response.write "<h1>Ping success</h1>"
      end
    end
  end
end
