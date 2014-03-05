require "ups_shipping/version"

module UpsShipping
  require 'net/http'
  require 'uri'

  class UpsShipping
    attr_reader :products, :shipping_address, :shipping_method

    def initialize(args = {})
      @products = args.fetch(:products, [])
      @shipping_method = args[:shipping_method]
      @shipping_address = args[:shipping_address]
    end

    def request_shipping_rate
      uri = URI.parse(UPS_API['confirm_url'])
      https = Net::HTTP.new(uri.host, uri.port)
      https.use_ssl = true       

      headers = {'Content-Type' => 'text/xml'}
      request = Net::HTTP::Post.new(uri.path, headers)
      request.body = xml_for_initial_request

      begin
        response = https.request(request)
        shipment_confirm_response = Nokogiri::XML(response.body)
        shipping_cost = shipment_confirm_response.xpath("//TotalCharges//MonetaryValue").text
        if shipping_cost.blank?
          return nil
        else
          return (shipping_cost.to_f + extra_cost).round(2)
        end
      rescue => error
        Rails.logger.info "UPS Error => #{error}"
        return ""
      end
    end

    def extra_cost
      2.00
    end

    def xml_for_initial_request
      body = ''
      body << access_request.to_xml(root: "AccessRequest")
      body << shipment_confirm_request.to_xml(root: "ShipmentConfirmRequest")
      body
    end

    def access_request
      {
        "AccessLicenseNumber" => UPS_API["access_key"],
        "UserId" => UPS_API["user_id"],
        "Password" => UPS_API["password"]
      }
    end

    def shipment_confirm_request
      {
        "Request" => request,
        "Shipment" => shipment,
        "LabelSpecification" => label_specification
      }
    end

    def request
      {
        "TransactionReference" => transaction_reference,
        "RequestAction" => "ShipConfirm",
        "RequestOption" => "nonvalidate"
      }
    end

    def transaction_reference
      {
        "XpciVersion" => "1.0001"
      }
    end

    def shipment
      shipment = {}.compare_by_identity
      shipment["Shipper"] = shipper
      shipment["ShipTo"] = ship_to
      shipment["Service"] = service
      shipment["PaymentInformation"] = payment_information

      package_weights.each do |weight|
        shipment["Package"] = package(weight)
      end
      shipment
    end

    def package_weights
      weights = []
      total = total_weight_of_products
      while total > 0
        if total >= 30
          weights << 30
          total -= 30
        else
          weights << total
          total = 0
        end
      end
      return weights
    end

    def shipper
      {
        "Name" => "Whitehurst & Clark Inc.",
        "AttentionName" => "Jason Low",
        "PhoneNumber" => "212-779-4400",
        "ShipperNumber" => UPS_API["account_number"],
        "Address" => shipper_address
      }
    end

    def ship_to
      raise "#ship_to method must be implemented."
    end

    def service
      raise "#service method must be implemented."
    end

    def payment_information
      {
        "Prepaid" => prepaid
        }
    end

    def package(weight)
      {
        "PackagingType" => packaging_type,
        "PackageWeight" => package_weight(weight)
      }
    end

    def label_specification
      {
        "LabelPrintMethod" => label_print_method,
        "HTTPUserAgent" => "Mozilla/4.5",
        "LabelImageFormat" => label_image_format
      }
    end

    def shipper_address
      {
        "AddressLine1" => WAREHOUSE_ADDRESS["AddressLine1"],
        "City" => WAREHOUSE_ADDRESS["City"],
        "StateProvinceCode" => WAREHOUSE_ADDRESS["StateProvinceCode"],
        "CountryCode" => WAREHOUSE_ADDRESS["CountryCode"],
        "PostalCode" => WAREHOUSE_ADDRESS["PostalCode"]
      }
    end

    def recipient_address
      raise "#recipient_address method must be implemented."
    end

    def prepaid
      {
        "BillShipper" => bill_shipper
        }
    end

    def bill_shipper
      {
        "AccountNumber" => UPS_API["account_number"]
        }
    end

    def credit_card
      {
        "Type" => UPS_API['cc_type'],
        "Number" => UPS_API['cc_number'],
        "ExpirationDate" => UPS_API['cc_expiration_date']
      }
    end

    def packaging_type
      {
        "Code" => "02"
      }
    end

    def package_weight(weight)
      {
        "Weight" => weight
      }
    end

    def label_print_method
      {
        "Code" => "GIF"
      }
    end

    def label_image_format
      {
        "Code" => "GIF"
      }
    end

    def total_weight_of_products
      products.map(&:weight_in_pounds).inject(0, :+)
    end

  end
  
  class UpsShippingEstimator < UpsShipping

    def ship_to
      {
        "CompanyName" => "Test",
        "AttentionName" => "Test",
        "PhoneNumber" => "1231231234",
        "Address" => recipient_address,
        "ResidentialAddress" => nil
      }
    end

    def recipient_address
      {
        "AddressLine1" => "Test",
        "City" => shipping_address['city'],
        "StateProvinceCode" => shipping_address['state'],
        "CountryCode" => 'US',
        "PostalCode" => shipping_address['zip_code']
      }
    end

    def service
      {
        "Code" => shipping_method.ups_code,
        "Description" => UPS_SERVICE_DESCRIPTIONS[shipping_method.ups_code]
      }
    end

  end
  
  class UpsShippingQuote < UpsShipping

    def ship_to
      {
        "CompanyName" => shipping_address.company,
        "AttentionName" => shipping_address.name,
        "PhoneNumber" => shipping_address.phone,
        "Address" => recipient_address,
        "ResidentialAddress" => nil
      }
    end

    def recipient_address
      {
        "AddressLine1" => shipping_address.address,
        "AddressLine2" => shipping_address.address_2,
        "City" => shipping_address.city,
        "StateProvinceCode" => shipping_address.state.code,
        "CountryCode" => 'US',
        "PostalCode" => shipping_address.postal_code
      }
    end

    def service
      {
        "Code" => shipping_method.ups_code,
        "Description" => UPS_SERVICE_DESCRIPTIONS[shipping_method.ups_code]
      }
    end
  end
end
