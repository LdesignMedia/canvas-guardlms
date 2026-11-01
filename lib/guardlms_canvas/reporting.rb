# frozen_string_literal: true
module GuardlmsCanvas
  module Reporting
    def self.push(force: false, store: Store, env: ENV, client_factory: ->(config) { Connector.new(env: config) })
      now = Time.now.to_i
      reservation = store.update do |data|
        next nil if data[:managed] && data[:disabled]
        next nil unless Configuration.connected?(data, env)
        next nil if data[:lease_until].to_i > now
        next nil if !force && (data[:daily_enabled] == false || data[:next_attempt_at].to_i > now || data[:auth_rejected_at])
        data[:configuration_id] ||= SecureRandom.hex(16)
        data[:attempt_id] = SecureRandom.hex(16)
        data[:lease_until] = now + 120
        data[:last_attempt_at] = now
        [data.dup, data[:configuration_id], data[:attempt_id]]
      end
      return nil unless reservation

      data, generation, attempt = reservation
      client = client_factory.call(Configuration.environment(data, env))
      begin
        result = client.push(client.inventory(canvas: Canvas, rails_version: Rails.version))
        finish(store, generation, attempt) do |current|
          current[:last_success_at] = Time.now.to_i
          current[:next_attempt_at] = Time.now.to_i + 86_400
          current[:components_upserted] = result.fetch("components_upserted")
          current[:website_id] = result.fetch("website_id")
          current[:last_http_status] = 200
          current[:failure_count] = 0
          current.delete(:last_error)
          current.delete(:auth_rejected_at)
        end
        result
      rescue StandardError => error
        finish(store, generation, attempt) do |current|
          current[:failure_count] = current[:failure_count].to_i + 1
          current[:next_attempt_at] = Time.now.to_i + [300 * (2**[current[:failure_count] - 1, 8].min), 21_600].min
          current[:last_http_status] = error.is_a?(Error) ? error.status : nil
          current[:auth_rejected_at] ||= Time.now.to_i if [401, 403].include?(current[:last_http_status])
          # Never persist exception text from Canvas, the DB or third-party plugins.
          current[:last_error] = error.is_a?(Error) ? error.message : "Inventory collection failed; inspect Canvas server logs"
        end
        raise error if error.is_a?(Error)
        raise Error, "Inventory collection failed; inspect Canvas server logs"
      end
    end

    def self.finish(store, generation, attempt)
      store.update do |current|
        next unless current[:configuration_id] == generation && current[:attempt_id] == attempt
        yield current
        current.delete(:lease_until)
        current.delete(:attempt_id)
      end
    end

    def self.enqueue
      delay(singleton: "guardlms:inventory", on_conflict: :patient, max_attempts: 1).run
    end

    def self.run
      push
    rescue Error
      # Persisted backoff is retried by the five-minute periodic job. Permanent
      # authentication failures wait for reconnect or an explicit manual push.
      nil
    end
  end
end
