# frozen_string_literal: true
module GuardlmsCanvas
  module Connection
    def self.start(session, user_id, store: Store, env: ENV)
      data = store.read
      config = Configuration.environment(data, env)
      site = Configuration.url(config["GUARDLMS_SITE_URL"], "Canvas site URL")
      dashboard = Configuration.url(env["GUARDLMS_DASHBOARD_URL"] || data[:dashboard_url] || Configuration::DEFAULT_DASHBOARD, "GuardLMS dashboard URL", origin: true)
      state = SecureRandom.hex(32)
      session[:guardlms_connect] = {
        "state" => state, "user_id" => user_id, "expires" => Time.now.to_i + 900,
        "siteurl" => site, "api_url" => config["GUARDLMS_API_URL"], "generation" => data[:configuration_id]
      }
      dashboard + "/connect/canvas?" + URI.encode_www_form(siteurl: site, state: state, callback: site + Configuration::CALLBACK_PATH)
    end

    def self.complete(session, user_id, code, state, store: Store, env: ENV, client_factory: ->(config) { Connector.new(env: config) })
      pending = session.delete(:guardlms_connect)
      unless pending && pending["user_id"] == user_id && pending["expires"].to_i > Time.now.to_i &&
             state.to_s.match?(/\A[0-9a-f]{64}\z/) && code.to_s.match?(/\A[A-Za-z0-9]{64}\z/) &&
             ActiveSupport::SecurityUtils.secure_compare(pending["state"], state)
        raise Error, "Connection request expired or is invalid. Start Connect to GuardLMS again."
      end
      data = store.read
      config = Configuration.environment(data, env)
      unless data[:configuration_id] == pending["generation"] && config["GUARDLMS_SITE_URL"] == pending["siteurl"] && config["GUARDLMS_API_URL"] == pending["api_url"]
        raise Error, "Settings changed while connecting. Start Connect to GuardLMS again."
      end
      result = client_factory.call(config).exchange(code: code, state: state, siteurl: pending["siteurl"])
      expires = result["expires_at"] && Time.iso8601(result["expires_at"]).utc.iso8601
      store.update do |current|
        raise Error, "Settings changed while connecting. Start again." unless current[:configuration_id] == pending["generation"]
        Configuration.reset_connection(current)
        current.merge!(api_key: result.fetch("token"), website_id: result.fetch("website_id"), expires_at: expires,
                       site_url: pending["siteurl"], api_url: pending["api_url"], connected_at: Time.now.to_i,
                       managed: true, disabled: false, daily_enabled: true)
        verification = result["verification_token"].to_s
        current[:verification_token] = verification if verification.match?(/\A[a-zA-Z0-9_-]{16,255}\z/)
      end
    rescue ArgumentError
      raise Error, "GuardLMS returned an invalid key expiry"
    end

    def self.disconnect(store: Store)
      store.update do |data|
        Configuration.reset_connection(data)
        data.merge!(managed: true, disabled: true)
      end
    end
  end
end
