module AddressStandardization
  # See <http://code.google.com/apis/maps/documentation/geocoding/>
	# Lets put addr2 in here
  class GoogleMaps < AbstractService
    class << self
      attr_accessor :api_key
    
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
        res = Net::HTTP.get_response(uri)
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
