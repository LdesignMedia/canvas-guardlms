# frozen_string_literal: true
require "uri"
require "securerandom"
require "time"

module GuardlmsCanvas
  module Configuration
    DEFAULT_DASHBOARD = "https://dashboard.guardlms.com"
    DEFAULT_API = "https://api.guardlms.com"
    CALLBACK_PATH = "/plugins/guardlms/callback"
    SECRET_KEYS = %i[api_key api_key_enc api_key_salt api_key_dec].freeze

    def self.url(value, label, origin: false)
      uri = URI.parse(value.to_s.strip)
      unless uri.is_a?(URI::HTTPS) && uri.host && !uri.userinfo && !uri.query && !uri.fragment
        raise Error, "#{label} must be an HTTPS URL without credentials, query or fragment"
      end
      if origin && !["", "/"].include?(uri.path)
        raise Error, "#{label} must be an HTTPS origin without a path"
      end
      raise Error, "#{label} is too long" if uri.to_s.length > 255
      uri.to_s.sub(%r{/+\z}, "")
    rescue URI::InvalidURIError
      raise Error, "#{label} is not a valid HTTPS URL"
    end

    def self.environment(data, env = ENV)
      {
        "GUARDLMS_SITE_URL" => env["GUARDLMS_SITE_URL"] || data[:site_url],
        "GUARDLMS_API_URL" => env["GUARDLMS_API_URL"] || data[:api_url] || DEFAULT_API,
        "GUARDLMS_WEBSERVER" => env["GUARDLMS_WEBSERVER"] || data[:webserver],
        "GUARDLMS_API_KEY" => env["GUARDLMS_API_KEY"] || data[:api_key_dec]
      }.transform_values { |value| value.to_s }
    end

    def self.connected?(data, env = ENV)
      !environment(data, env)["GUARDLMS_API_KEY"].empty?
    end

    def self.status(data, env = ENV, now: Time.now)
      return connected?(data, env) ? "Reporting paused" : "Disconnected" if data[:disabled] && data[:managed]
      return "Not connected" unless connected?(data, env)
      return "Reconnect required" if data[:auth_rejected_at] || (data[:expires_at] && Time.iso8601(data[:expires_at]) <= now)
      return "Push failed" if data[:last_error]
      if data[:daily_enabled] != false && data[:last_success_at] && now.to_i - data[:last_success_at].to_i > 172_800
        return "Inventory overdue — check Canvas background workers"
      end
      data[:last_success_at] ? "Connected" : "Connected — awaiting first push"
    rescue ArgumentError
      "Reconnect required"
    end

    def self.expiry_warning(data, now: Time.now)
      return unless data[:expires_at]
      expires = Time.iso8601(data[:expires_at])
      return unless expires > now && expires <= now + 30 * 86_400
      "Inventory key expires on #{expires.utc.strftime('%Y-%m-%d')}. Reconnect before expiry to keep reporting."
    rescue ArgumentError
      nil # The connection status already asks the administrator to reconnect.
    end

    def self.dashboard_link(data, env = ENV)
      origin = url(env["GUARDLMS_DASHBOARD_URL"] || data[:dashboard_url] || DEFAULT_DASHBOARD, "GuardLMS dashboard URL", origin: true)
      id = data[:website_id]
      id.is_a?(Integer) && id.positive? ? "#{origin}/websites/#{id}" : origin
    rescue Error
      nil
    end

    def self.destination_label(data, env = ENV)
      api = url(environment(data, env)["GUARDLMS_API_URL"], "GuardLMS API URL", origin: true)
      dashboard = url(env["GUARDLMS_DASHBOARD_URL"] || data[:dashboard_url] || DEFAULT_DASHBOARD, "GuardLMS dashboard URL", origin: true)
      return "Production" if api == DEFAULT_API && dashboard == DEFAULT_DASHBOARD
      return "Staging" if api == "https://api-staging.guardlms.com" && dashboard == "https://dashboard-staging.guardlms.com"
      "Custom GuardLMS instance"
    rescue Error
      "Invalid GuardLMS destination"
    end

    def self.reset_connection(data)
      SECRET_KEYS.each { |key| data.delete(key) }
      %i[verification_token website_id expires_at connected_at auth_rejected_at last_success_at last_attempt_at last_error
         last_http_status components_upserted failure_count next_attempt_at lease_until attempt_id pending_state pending_until].each { |key| data.delete(key) }
      data[:configuration_id] = SecureRandom.hex(16)
    end

    def self.save(input, store: Store, env: ENV)
      values = {
        site_url: url(env["GUARDLMS_SITE_URL"] || input[:site_url], "Canvas site URL"),
        api_url: url(env["GUARDLMS_API_URL"] || input[:api_url] || DEFAULT_API, "GuardLMS API URL", origin: true),
        dashboard_url: url(env["GUARDLMS_DASHBOARD_URL"] || input[:dashboard_url] || DEFAULT_DASHBOARD, "GuardLMS dashboard URL", origin: true),
        daily_enabled: input[:daily_enabled].to_s == "1"
      }
      key = input[:api_key].to_s.strip
      raise Error, "The inventory key is invalid" if key.length > 512 || key.match?(/[\r\n]/)
      store.update do |data|
        old_env = environment(data, env)
        changed_target = old_env["GUARDLMS_SITE_URL"] != values[:site_url] || old_env["GUARDLMS_API_URL"] != values[:api_url]
        reset_connection(data) if changed_target || !key.empty?
        data.merge!(values)
        data[:api_key] = key unless key.empty? || env["GUARDLMS_API_KEY"]
        data[:configuration_id] = SecureRandom.hex(16)
        data.delete(:lease_until)
        data.delete(:attempt_id)
        data[:managed] = true
        data[:disabled] = input[:enabled].to_s != "1"
      end
    end
  end
end
