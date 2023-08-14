require 'erb'
require 'tempfile'

module QRISConverter
  class QROutput
    attr_accessor :lite
    attr_accessor :code
    attr_accessor :value
    attr_accessor :url
    attr_accessor :data
    attr_accessor :real_mark
    attr_accessor :debug
    
    def process(template)
      template.result(binding)
    end
  end
  WatermarkQueue = {}
  class Controller
    def initialize(req, resp)
      @request = req
      @response = resp
      @layout = nil
      @true_watermark = false
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
      qr.real_mark = @true_watermark
      template = ERB.new(File.read(File.join(Dir.pwd, 'views', @layout + '.html.erb')))
      @response.write qr.process(template)
    end
    def _process_image_output(processor, url)
      size = 960
      tmp_logo = nil
      qr_logo = nil

      unless url.nil? then
        uri = URI(url)
        url_hash = Digest::SHA256.hexdigest(url)
        
        if WatermarkQueue.key?(url) then
          tmp_logo = WatermarkQueue[url]
        elsif defined?(MiniMagick) then
          mgc_logo = MiniMagick::Image.open(url)
          logo_size = size / 5
          logo_border = logo_size / 10
          logo_final = logo_size - (logo_border)
            mgc_logo.format('png') do |op|
            op.resize sprintf("%1$dx%1$d", logo_final)
            op.alpha 'set'
            op.bordercolor 'none'
            op.border logo_border
          end
          tmp_logo = Tempfile.new(url_hash)
          tmp_logo.write mgc_logo.to_blob
          WatermarkQueue[url] = tmp_logo
        else
          tmp_logo = Tempfile.new(url_hash)
          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.port == 443) do |http|
            req = Net::HTTP::Get.new(uri.path)
            res = http.request req
            res.value
          rescue => e
            p e
          else
            tmp_logo.write res.body
            WatermarkQueue[url] = tmp_logo
          end
        end
        if tmp_logo then
          qr_logo = ChunkyPNG::Image.from_file(tmp_logo.path)
        end
      end
      
      unless qr_logo.nil? then
        qr_back = ChunkyPNG::Image.new(qr_logo.width, qr_logo.height, '#ffffff')
        x_off = (processor.width - qr_back.width) / 2
        y_off = (processor.height - qr_back.height) / 2
        processor.replace! qr_back, x_off, y_off
        processor.compose! qr_logo, x_off, y_off
        @true_watermark = true
      end
      
      processor
    rescue => e
      
    ensure
      WatermarkQueue.keys.slice(0...-5).each do |queue_key|
        queue_tmp = WatermarkQueue.delete(queue_key)
        queue_tmp&.close
        queue_tmp&.unlink
      end if WatermarkQueue.size > 10
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
