module AddressStandardization
  # See <http://code.google.com/apis/maps/documentation/geocoding/>
	# Lets put addr2 in here
  class GoogleMaps < AbstractService
    class << self
      attr_accessor :api_key
      attr_accessor :proxy
      attr_accessor :proxy_error_callback
      attr_accessor :proxy_max_request_time
      attr_accessor :slow_proxy_callback
    
    protected
      # much of this code was borrowed from GeoKit, thanks...

      def get_live_response(address_info)
        #raise "API key not specified.\nCall AddressStandardization::GoogleMaps.api_key = '...' before you call .standardize()." unless GoogleMaps.api_key
        
        address_info = address_info.stringify_keys
        
        address_str = [
          address_info["street"],
          address_info["city"],
          (address_info["state"] || address_info["province"]),
          address_info["zip"]
        ].compact.join(" ")

 				# Check if address contains a unit indicator #,apt,unit
        if %w(#).any? {|str| address_str.downcase.include? str}
          address_str.gsub!("#", "UNIT ") #UNIT WILL ALWAYS TURN INTO "#" IN GOOGLE MAPS
        end

        url = "http://maps.google.com/maps/geo?q=#{address_str.url_escape}&output=xml&oe=utf-8"

        AddressStandardization.debug "[GoogleMaps] Hitting URL: #{url}"
        uri = URI.parse(url)
        
        # Proxy given? Use it.
        if proxy
          # Cycle through our proxy list
          while true
            # our proxy list may be empty.. break the loop and try a regular get
            unless proxy_url = (proxy.kind_of?(Proc) ? proxy.call : proxy)
              AddressStandardization.debug "[GoogleMaps] Proxy list appears to be empty -- bypassing proxy."
              res = Net::HTTP.get_response(uri)
              break
            end

            AddressStandardization.debug "[GoogleMaps] Using proxy: #{proxy_url}"
              
            # try to request uri via proxy
            bm = Benchmark.measure do
              proxy_host, proxy_port = proxy_url.split(':')
              http_proxy = Net::HTTP::Proxy(proxy_host, proxy_port)
              
              res = nil
              start_time = Time.now
              proxy_thread = Thread.new do
                res = http_proxy.get_response(uri) rescue nil
              end
              
              # Wait for response for a maximum of `proxy_max_request_time` secs
              while Time.now < (start_time + proxy_max_request_time)
                break unless proxy_thread.alive?
                sleep 0.1
              end

              # Kill the proxy thread, if still running since it is no longer useful for us after this point
              proxy_thread.kill if proxy_thread.alive?
            end

            AddressStandardization.debug "--------------------------------------------------"
            AddressStandardization.debug "Time ellapsed: #{bm.to_s}"
            AddressStandardization.debug "--------------------------------------------------"
            
            if proxy_max_request_time && bm.real > proxy_max_request_time
              AddressStandardization.debug "WARNING: Slow proxy"
              slow_proxy_callback.call(proxy) if slow_proxy_callback
            end
            
            AddressStandardization.debug "Response type was: #{res.class.to_s}"
            # break the loop if we got a successful response          
            break if res.is_a?(Net::HTTPSuccess)

            # report bad proxy and try again...
            proxy_error_callback.call(proxy) if proxy_error_callback
          end
        # Direct request
        else
          res = Net::HTTP.get_response(uri)
        end

        return unless res.is_a?(Net::HTTPSuccess)
        
        content = res.body
        AddressStandardization.debug "[GoogleMaps] Response body:"
        AddressStandardization.debug "--------------------------------------------------"
        AddressStandardization.debug content
        AddressStandardization.debug "--------------------------------------------------"
        xml = Nokogiri::XML(content)
        xml.remove_namespaces! # good or bad? I say good.
        return unless xml.at("/kml/Response/Status/code").inner_text == "200"
        
        addr = {}
        
        full_street = get_inner_text(xml, '//ThoroughfareName').to_s
        if full_street.include?("#")
          addr2 = "##{full_street.split('#').last}"
        else
          addr2 = nil
        end

        addr[:street]   = full_street.split('#').first
        addr[:addr2]    = addr2
        addr[:city]     = get_inner_text(xml, '//LocalityName').to_s
        addr[:province] = addr[:state] = get_inner_text(xml, '//AdministrativeAreaName').to_s
        addr[:zip]      = addr[:postalcode] = get_inner_text(xml, '//PostalCodeNumber').to_s
        addr[:country]  = get_inner_text(xml, '//CountryName').to_s
        
        return if addr[:street] =~ /^\s*$/ or addr[:city]  =~ /^\s*$/
        
        Address.new(addr)
      end
      
    private
      def get_inner_text(xml, xpath)
        lambda {|x| x && x.inner_text.upcase }.call(xml.at(xpath))
      end
    end
  end
end
