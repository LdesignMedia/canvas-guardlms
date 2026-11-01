# frozen_string_literal: true
require "json"
require "net/http"
require "openssl"
require "uri"

module GuardlmsCanvas
  class Error < StandardError; end

  # Deliberately never serializes plugin settings, accounts, courses or users.
  class Connector
    PUSH_PATH = "/api/externalpush/canvas"

    def initialize(env: ENV, http_factory: ->(uri) { Net::HTTP.new(uri.host, uri.port, nil) })
      @env = env
      @http_factory = http_factory
    end

    def inventory(canvas:, rails_version:, ruby_version: RUBY_VERSION, now: Time.now)
      plugins = canvas::Plugin.all.map do |plugin|
        {
          id: bounded(plugin.id, 255),
          version: bounded(plugin.version, 100),
          enabled: !!plugin.enabled?
        }
      end
      raise Error, "Canvas has more than 2000 registered plugins; inventory was not sent" if plugins.size > 2000

      {
        siteurl: site_url,
        generatedtime: now.to_i,
        canvas: { version: bounded(canvas.revision, 100), plugins: plugins },
        ruby: { version: bounded(ruby_version, 50) },
        rails: { version: bounded(rails_version, 50) }
      }
    end

    def push(payload)
      endpoint = https_url(@env.fetch("GUARDLMS_API_URL", "https://api.guardlms.com"), "GUARDLMS_API_URL")
      raise Error, "GUARDLMS_API_URL must be an origin without a path" unless ["", "/"].include?(endpoint.path)
      endpoint.path = PUSH_PATH
      token = @env.fetch("GUARDLMS_API_KEY", "")
      raise Error, "Set GUARDLMS_API_KEY to the website-bound inventory key" if token.empty? || token.match?(/[\r\n]/)
      raise Error, "Payload site URL differs from GUARDLMS_SITE_URL" unless payload[:siteurl] == site_url

      request = Net::HTTP::Post.new(endpoint.request_uri)
      request["Authorization"] = "Bearer #{token}"
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json"
      request["User-Agent"] = "GuardLMS-Canvas/0.1.0"
      request.body = JSON.generate(payload)
      http = @http_factory.call(endpoint)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.open_timeout = 10
      http.read_timeout = 30
      http.write_timeout = 30
      http.max_retries = 0
      response = http.request(request)
      case response.code.to_i
      when 200
        begin
          result = JSON.parse(response.body)
        rescue JSON::ParserError
          raise Error, "GuardLMS returned invalid JSON; inventory acceptance is unknown"
        end
        unless result.is_a?(Hash) && result["data"].is_a?(Hash) && result["data"]["website_id"].is_a?(Integer)
          raise Error, "GuardLMS returned an unexpected response; inventory acceptance is unknown"
        end
        result["data"]
      when 401, 403
        raise Error, "GuardLMS refused the key; replace it with a valid website-bound inventory key"
      when 422
        raise Error, "GuardLMS rejected the inventory; check GUARDLMS_SITE_URL matches the registered website and review the payload schema"
      else
        # Never follow redirects with a credential or echo remote bodies into logs.
        raise Error, "GuardLMS inventory push failed (HTTP #{response.code}); retry on the next scheduled run"
      end
    rescue Timeout::Error, SocketError, IOError, SystemCallError, OpenSSL::SSL::SSLError
      raise Error, "GuardLMS connection failed; check connectivity and TLS, then retry"
    end

    private

    def site_url
      uri = https_url(@env.fetch("GUARDLMS_SITE_URL", ""), "GUARDLMS_SITE_URL")
      url = uri.to_s.sub(%r{/+\z}, "")
      raise Error, "GUARDLMS_SITE_URL exceeds 255 characters" if url.length > 255
      url
    end

    def https_url(value, name)
      uri = URI.parse(value)
      unless uri.is_a?(URI::HTTPS) && uri.host && !uri.userinfo && !uri.query && !uri.fragment
        raise Error, "#{name} must be an HTTPS URL without credentials, query or fragment"
      end
      uri
    rescue URI::InvalidURIError
      raise Error, "#{name} is not a valid HTTPS URL"
    end

    def bounded(value, limit)
      return nil if value.nil? || value.to_s.strip.empty?
      text = value.to_s
      raise Error, "Canvas metadata exceeds the inventory field limit" if text.length > limit
      text
    end
  end
end
