module Swagger
  module Diff
    class Diff
      def initialize(old, new)
        @new_specification = Swagger::Diff::Specification.new(new)
        @old_specification = Swagger::Diff::Specification.new(old)
      end

      def changes
        @changes ||= {
          new_endpoints: new_endpoints.to_a.sort,
          removed_endpoints: missing_endpoints.to_a.sort,
          new_request_params: new_or_changed_request_params,
          removed_request_params: incompatible_request_params,
          new_response_attributes: new_or_changed_response_attributes,
          removed_response_attributes: incompatible_response_attributes
        }
      end

      def changes_message(csvOrYaml)
        @outputFormat = csvOrYaml
        msg = ''
        #Header row only for CSV and only if there are actually changes
        if @outputFormat == "csv" && (changed_endpoints_message + changed_params_message + changed_attrs_message != "")
          msg += 'Endpoint,OperationId,Change,Category,Sub Category,Attribute'
        end
        msg += changed_endpoints_message + changed_params_message + changed_attrs_message
        msg
      end

      def compatible?
        endpoints_compatible? && requests_compatible? && responses_compatible?
      end

      def incompatibilities
        @incompatibilities ||= {
          endpoints: missing_endpoints.to_a.sort,
          request_params: incompatible_request_params,
          response_attributes: incompatible_response_attributes
        }
      end

      def incompatibilities_message(csvOrYaml)
        @outputFormat = csvOrYaml
        msg = ''
        if @outputFormat == "csv"
          #Header row only for CSV and only if there are actually incompatibilities
          if(endpoints_message('missing,n/a,n/a', incompatibilities[:endpoints]) != "")
            msg += 'Endpoint,OperationId,Change,Category,Sub Category,Attribute'
          end
          msg += endpoints_message('missing,n/a,n/a', incompatibilities[:endpoints])
        else
          msg += endpoints_message('missing', incompatibilities[:endpoints])
        end
        msg += params_message('incompatible', incompatibilities[:request_params])
        msg += attributes_message('incompatible', incompatibilities[:response_attributes])
        msg
      end

      private

      def changed_endpoints_message
        msg = ''
        if @outputFormat == "csv"
            msg += endpoints_message('new,n/a,n/a', changes[:new_endpoints])
            msg += endpoints_message('removed,n/a,n/a', changes[:removed_endpoints])
        else
          msg += endpoints_message('new', changes[:new_endpoints])
          msg += endpoints_message('removed', changes[:removed_endpoints])
        end
        msg
      end

      def changed_params_message
        msg = ''
        msg += params_message('new', changes[:new_request_params])
        msg += params_message('removed', changes[:removed_request_params])
        msg
      end

      def changed_attrs_message
        msg = ''
        msg += attributes_message('new', changes[:new_response_attributes])
        msg += attributes_message('removed', changes[:removed_response_attributes])
        msg
      end

      def endpoints_message(type, endpoints)
        if endpoints.empty?
          ''
        else
          if @outputFormat == "csv"
            msg = ''
            endpoints.each do |endpoint|
              urlSplit = endpoint.split(" operationId:")
              msg += "#{urlSplit[0]},#{urlSplit[1]},#{type},endpoints\n"
            end
          else
            msg = "- #{type} endpoints\n"
            endpoints.each do |endpoint|
              msg += "  - #{endpoint}\n"
            end
          end
          msg
        end
      end

      def inner_message(nature, type, collection)
        if collection.nil? || collection.empty?
          ''
        else
          if @outputFormat == "csv"
            msg = ''
            collection.sort.each do |endpoint, attributes|
              urlSplit = endpoint.split(" operationId:")
              attributes.each do |attribute|
                msg += "#{urlSplit[0]},#{urlSplit[1]},#{nature},#{type},#{attribute}\n"
              end
            end
          else
            msg = "- #{nature} #{type}\n"
            collection.sort.each do |endpoint, attributes|
              msg += "  - #{endpoint}\n"
              attributes.each do |attribute|
                msg += "    - #{attribute}\n"
              end
            end
          end
          msg
        end
      end

      def params_message(type, params)
        inner_message(type, 'request params', params)
      end

      def attributes_message(type, attributes)
        inner_message(type, 'response attributes', attributes)
      end

      def missing_endpoints
        @old_specification.endpoints - @new_specification.endpoints
      end

      def new_endpoints
        @new_specification.endpoints - @old_specification.endpoints
      end

      def change_hash(enumerator)
        ret = {}
        enumerator.each do |key, val|
          ret[key] ||= []
          ret[key] << val
        end
        ret
      end

      def incompatible_request_params
        change_hash(incompatible_request_params_enumerator)
      end

      def new_or_changed_request_params
        if @outputFormat == "csv"
          enumerator = changed_request_params_enumerator(
            @new_specification,
            @old_specification,
            '%<req>s is no longer required,n/a',
            'new request param,%<req>s'
          )  
        else
          enumerator = changed_request_params_enumerator(
            @new_specification,
            @old_specification,
            '%<req>s is no longer required,n/a',
            'new request param: %<req>s'
          )  
        end
        change_hash(enumerator)
      end

      def new_child?(req, old)
        idx = req.rindex('/')
        return false unless idx
        key = req[0..idx]
        old.none? { |param| param.start_with?(key) }
      end

      def changed_request_params_enumerator(from, to, req_msg, missing_msg)
        Enumerator.new do |yielder|
          from.request_params.each do |key, old_params|
            new_params = to.request_params[key]
            next if new_params.nil?
            (new_params[:required] - old_params[:required]).each do |req|
              next if new_child?(req, old_params[:all])
              yielder << [key, format(req_msg, req: req)]
            end
            (old_params[:all] - new_params[:all]).each do |req|
              yielder << [key, format(missing_msg, req: req)]
            end
          end
        end.lazy
      end

      def incompatible_request_params_enumerator
        if @outputFormat == "csv"
          changed_request_params_enumerator(
            @old_specification,
            @new_specification,
            'new required request param,%<req>s',
            'missing request param,%<req>s'
          )
        else
          changed_request_params_enumerator(
            @old_specification,
            @new_specification,
            'new required request param: %<req>s',
            'missing request param: %<req>s'
          )
        end
      end

      def incompatible_response_attributes
        change_hash(incompatible_response_attributes_enumerator)
      end

      def new_or_changed_response_attributes
        enumerator = changed_response_attributes_enumerator(
          @new_specification,
          @old_specification,
          'new attribute for %<code>s response: %<resp>s',
          'new %<code>s response'
        )
        change_hash(enumerator)
      end

      def changed_response_attributes_enumerator(from, to, attr_msg, code_msg)
        Enumerator.new do |yielder|
          from.response_attributes.each do |key, old_attributes|
            new_attributes = to.response_attributes[key]
            next if new_attributes.nil?
            old_attributes.keys.each do |code|
              if new_attributes.key?(code)
                (old_attributes[code] - new_attributes[code]).each do |resp|
                  yielder << [key, format(attr_msg, code: code, resp: resp)]
                end
              else
                yielder << [key, format(code_msg, code: code)]
              end
            end
          end
        end.lazy
      end

      def incompatible_response_attributes_enumerator
        if @outputFormat == "csv"
          changed_response_attributes_enumerator(
            @old_specification,
            @new_specification,
            'missing attribute from %<code>s response,%<resp>s',
            'missing %<code>s response,n/a'
          )
        else
          changed_response_attributes_enumerator(
            @old_specification,
            @new_specification,
            'missing attribute from %<code>s response: %<resp>s',
            'missing %<code>s response'
          )
        end
      end

      def endpoints_compatible?
        missing_endpoints.empty?
      end

      def requests_compatible?
        incompatible_request_params_enumerator.none?
      end

      def responses_compatible?
        incompatible_response_attributes_enumerator.none?
      end
    end
  end
end
