module QRISConverter
  class Router
    PATTERNS = [
      ['/', :GET, :load_page],
      ['/', :POST, :process_qrcode],
    ].freeze
    
    def initialize(req)
      @request = req
      @response = initialize_response
    end
    
    public
    def process
      @route_data = determine_route
      return interrupt(404, "<h1>Page Not Found</h1>") if @route_data.nil?
      @route_data[1].each do |k, v|
        @request.update_param k, v
      end
      Controller.new(@request, @response).send(@route_data[0][2])
      @response
    end
    
    private
    def initialize_response
      res = Rack::Response.new
      res.content_type = 'text/html'
      res.status = 200
      res
    end
    
    def determine_route
      input_fragments = @request.path.split('/').reject(&:empty?)
      route_params = {}
      route_data = PATTERNS.find do |route_config|
        route_raw_path, route_method, route_call = route_config
        route_fragments = route_raw_path.split('/').reject(&:empty?)
        next if @request.request_method != route_method.to_s
        next if input_fragments.size != route_fragments.size
        next unless route_fragments.each_with_index.all? do |k, i|
                next true if k[0] == ':'
                k == input_fragments[i]
              end
        param_indices = route_fragments.each_with_index.select do |k, i|
          k[0] == ':'
        end.map(&:last)
        route_params.clear
        param_indices.each do |i|
          route_params[route_fragments[i][1..-1]] = input_fragments[i]
        end
        true
      end
      return if route_data.nil?
      [route_data, route_params]
    end
    
    def interrupt(code, msg)
      @response.content_type = 'text/html'
      @response.status = code
      @response.write msg
      @response
    end
  end
end