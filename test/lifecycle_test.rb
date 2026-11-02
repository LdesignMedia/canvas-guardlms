# frozen_string_literal: true
gem "minitest", "~> 5.0"
require "minitest/autorun"
require "active_support/security_utils"
require_relative "../lib/guardlms_canvas"
module Canvas; end
module Rails
  def self.version = "8.0.5"
end

class LifecycleTest < Minitest::Test
  class MemoryStore
    attr_reader :data
    def initialize
      @data = {site_url: "https://canvas.example.com", api_url: "https://api.guardlms.com", api_key_dec: "secret", configuration_id: "initial", managed: true, disabled: false}
    end
    def read = @data.dup
    def update
      copy = @data.dup
      result = yield copy
      @data = copy
      result
    end
  end
  class Client
    attr_accessor :error, :on_push
    attr_reader :calls
    def initialize
      @calls = 0
    end
    def inventory(**) = {}
    def push(_payload)
      @calls += 1
      @on_push&.call
      raise @error if @error
      {"website_id" => 7, "components_upserted" => 46}
    end
    def exchange(**)
      {"token" => "new-secret", "website_id" => 7, "verification_token" => "public-token-123456", "expires_at" => "2030-01-01T00:00:00Z"}
    end
  end
  def setup
    @store = MemoryStore.new
    @client = Client.new
    @options = {store: @store, env: {}, client_factory: ->(_) { @client }}
  end
  def test_success_is_daily_and_manual_push_bypasses_schedule
    assert_equal 46, GuardlmsCanvas::Reporting.push(**@options)["components_upserted"]
    assert_nil GuardlmsCanvas::Reporting.push(**@options)
    assert_equal 1, @client.calls
    GuardlmsCanvas::Reporting.push(force: true, **@options)
    assert_equal 2, @client.calls
    assert_nil @store.data[:lease_until]
  end
  def test_transient_failures_back_off_and_recovery_clears_error
    @client.error = GuardlmsCanvas::Error.new("Unavailable", status: 503)
    assert_raises(GuardlmsCanvas::Error) { GuardlmsCanvas::Reporting.push(**@options) }
    assert_in_delta Time.now.to_i + 300, @store.data[:next_attempt_at], 2
    assert_nil GuardlmsCanvas::Reporting.push(**@options)
    assert_raises(GuardlmsCanvas::Error) { GuardlmsCanvas::Reporting.push(force: true, **@options) }
    assert_in_delta Time.now.to_i + 600, @store.data[:next_attempt_at], 2
    @client.error = nil
    GuardlmsCanvas::Reporting.push(force: true, **@options)
    assert_nil @store.data[:last_error]
    assert_equal 0, @store.data[:failure_count]
  end
  def test_rejected_key_stops_automatic_retries
    @client.error = GuardlmsCanvas::Error.new("Rejected", status: 401)
    assert_raises(GuardlmsCanvas::Error) { GuardlmsCanvas::Reporting.push(**@options) }
    @store.data[:next_attempt_at] = 0
    assert_nil GuardlmsCanvas::Reporting.push(**@options)
    assert_equal "Reconnect required", GuardlmsCanvas::Configuration.status(@store.read, {})
  end
  def test_disabled_reporting_and_active_lease_block_manual_pushes
    @store.data[:disabled] = true
    assert_nil GuardlmsCanvas::Reporting.push(force: true, **@options)
    @store.data[:disabled] = false
    @store.data[:lease_until] = Time.now.to_i + 30
    assert_nil GuardlmsCanvas::Reporting.push(force: true, **@options)
    assert_equal 0, @client.calls
  end
  def test_disconnect_during_request_does_not_restore_status_or_credentials
    @client.on_push = -> { GuardlmsCanvas::Connection.disconnect(store: @store) }
    GuardlmsCanvas::Reporting.push(**@options)
    assert @store.data[:disabled]
    assert_nil @store.data[:last_success_at]
    assert_nil @store.data[:api_key_dec]
    assert_nil GuardlmsCanvas::Reporting.push(force: true, **@options.merge(env: {"GUARDLMS_API_KEY" => "server-secret"}))
  end
  def test_save_preserves_blank_key_but_changes_generation
    GuardlmsCanvas::Configuration.save({site_url: "https://canvas.example.com", enabled: "1", daily_enabled: "1"}, store: @store, env: {})
    assert_equal "secret", @store.data[:api_key_dec]
    refute_equal "initial", @store.data[:configuration_id]
    GuardlmsCanvas::Configuration.save({site_url: "https://clone.example.com", enabled: "1"}, store: @store, env: {})
    assert_nil @store.data[:api_key_dec]
    assert_raises(GuardlmsCanvas::Error) { GuardlmsCanvas::Configuration.url("http://insecure.example", "URL") }
    assert_raises(GuardlmsCanvas::Error) { GuardlmsCanvas::Configuration.url("https://user:secret@example.com", "URL") }
  end
  def start_connection
    session = {}
    url = GuardlmsCanvas::Connection.start(session, 5, store: @store, env: {})
    assert_match %r{https://dashboard.guardlms.com/connect/canvas\?}, url
    [session, session[:guardlms_connect]["state"]]
  end
  def test_connection_binds_user_state_and_is_single_use
    session, state = start_connection
    GuardlmsCanvas::Connection.complete(session, 5, "a" * 64, state, **@options)
    assert_equal "new-secret", @store.data[:api_key]
    assert_equal "public-token-123456", @store.data[:verification_token]
    assert @store.data[:daily_enabled]
    assert_raises(GuardlmsCanvas::Error) { GuardlmsCanvas::Connection.complete(session, 5, "a" * 64, state, **@options) }
  end
  def test_connection_rejects_wrong_user_expired_state_and_settings_changes
    session, state = start_connection
    assert_raises(GuardlmsCanvas::Error) { GuardlmsCanvas::Connection.complete(session, 6, "a" * 64, state, **@options) }
    session, state = start_connection
    session[:guardlms_connect]["expires"] = Time.now.to_i - 1
    assert_raises(GuardlmsCanvas::Error) { GuardlmsCanvas::Connection.complete(session, 5, "a" * 64, state, **@options) }
    session, state = start_connection
    @store.data[:configuration_id] = "changed"
    assert_raises(GuardlmsCanvas::Error) { GuardlmsCanvas::Connection.complete(session, 5, "a" * 64, state, **@options) }
    assert_equal "secret", @store.data[:api_key_dec]
  end
  def test_unexpected_errors_do_not_persist_secret_messages
    @client.error = RuntimeError.new("password=private")
    error = assert_raises(GuardlmsCanvas::Error) { GuardlmsCanvas::Reporting.push(**@options) }
    refute_includes error.message, "private"
    refute_includes @store.data[:last_error], "private"
  end
  def test_ignored_snapshot_preserves_the_last_accepted_inventory_and_retries
    GuardlmsCanvas::Reporting.push(**@options)
    accepted_at = @store.data[:last_success_at]
    @client.error = GuardlmsCanvas::Error.new("GuardLMS ignored an older inventory; check the Canvas clock")
    assert_raises(GuardlmsCanvas::Error) { GuardlmsCanvas::Reporting.push(force: true, **@options) }
    assert_equal accepted_at, @store.data[:last_success_at]
    assert_equal 46, @store.data[:components_upserted]
    assert_equal "Push failed", GuardlmsCanvas::Configuration.status(@store.read, {})
    assert_in_delta Time.now.to_i + 300, @store.data[:next_attempt_at], 2
    assert_nil @store.data[:lease_until]
  end

  def test_status_distinguishes_paused_overdue_and_manually_scheduled_reporting
    now = Time.utc(2026, 11, 2)
    @store.data[:last_success_at] = now.to_i - 172_800
    assert_equal "Connected", GuardlmsCanvas::Configuration.status(@store.read, {}, now: now)
    @store.data[:last_success_at] -= 1
    assert_includes GuardlmsCanvas::Configuration.status(@store.read, {}, now: now), "Inventory overdue"
    @store.data[:daily_enabled] = false
    assert_equal "Connected", GuardlmsCanvas::Configuration.status(@store.read, {}, now: now)
    @store.data[:disabled] = true
    assert_equal "Reporting paused", GuardlmsCanvas::Configuration.status(@store.read, {}, now: now)
    @store.data.delete(:api_key_dec)
    assert_equal "Disconnected", GuardlmsCanvas::Configuration.status(@store.read, {}, now: now)
  end

  def test_expiry_warning_appears_before_expiry_and_status_requires_reconnection_afterwards
    now = Time.utc(2026, 11, 2)
    @store.data[:expires_at] = (now + 30 * 86_400).iso8601
    assert_includes GuardlmsCanvas::Configuration.expiry_warning(@store.read, now: now), "Reconnect before expiry"
    assert_equal "Connected — awaiting first push", GuardlmsCanvas::Configuration.status(@store.read, {}, now: now)
    @store.data[:expires_at] = (now + 30 * 86_400 + 1).iso8601
    assert_nil GuardlmsCanvas::Configuration.expiry_warning(@store.read, now: now)
    @store.data[:expires_at] = now.iso8601
    assert_nil GuardlmsCanvas::Configuration.expiry_warning(@store.read, now: now)
    assert_equal "Reconnect required", GuardlmsCanvas::Configuration.status(@store.read, {}, now: now)
    @store.data[:expires_at] = "not-a-date"
    assert_nil GuardlmsCanvas::Configuration.expiry_warning(@store.read, now: now)
    assert_equal "Reconnect required", GuardlmsCanvas::Configuration.status(@store.read, {}, now: now)
  end

  def test_dashboard_links_and_destination_labels_respect_overrides_and_validate_origins
    @store.data[:website_id] = 35
    assert_equal "https://dashboard.guardlms.com/websites/35", GuardlmsCanvas::Configuration.dashboard_link(@store.read, {})
    assert_equal "Production", GuardlmsCanvas::Configuration.destination_label(@store.read, {})
    env = {"GUARDLMS_API_URL" => "https://api-staging.guardlms.com/", "GUARDLMS_DASHBOARD_URL" => "https://dashboard-staging.guardlms.com/"}
    assert_equal "Staging", GuardlmsCanvas::Configuration.destination_label(@store.read, env)
    assert_equal "https://dashboard-staging.guardlms.com/websites/35", GuardlmsCanvas::Configuration.dashboard_link(@store.read, env)
    env["GUARDLMS_DASHBOARD_URL"] = "https://guardlms.example.com"
    assert_equal "Custom GuardLMS instance", GuardlmsCanvas::Configuration.destination_label(@store.read, env)
    @store.data[:website_id] = "35/other"
    assert_equal "https://guardlms.example.com", GuardlmsCanvas::Configuration.dashboard_link(@store.read, env)
    env["GUARDLMS_DASHBOARD_URL"] = "javascript:alert(1)"
    assert_nil GuardlmsCanvas::Configuration.dashboard_link(@store.read, env)
    assert_equal "Invalid GuardLMS destination", GuardlmsCanvas::Configuration.destination_label(@store.read, env)
  end

end
