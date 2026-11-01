# frozen_string_literal: true
gem "minitest", "~> 5.0"
require "minitest/autorun"
require "ostruct"
require_relative "../lib/guardlms_canvas/connector"

class ConnectorTest < Minitest::Test
  Plugin = Struct.new(:id, :version, :enabled_value, :settings) do
    def enabled? = enabled_value
  end
  FakeCanvas = Module.new
  FakeCanvas.const_set(:Plugin, Class.new do
    def self.all
      [ConnectorTest::Plugin.new("guardlms", "0.1.0", false, { password: "private" })]
    end
  end)
  def FakeCanvas.revision = "2026-10-21"

  class FakeHTTP
    attr_accessor :use_ssl, :verify_mode, :open_timeout, :read_timeout, :write_timeout, :max_retries
    attr_reader :requests
    def initialize(code = "200", body = '{"data":{"website_id":7,"components_upserted":4}}')
      @response = OpenStruct.new(code: code, body: body)
      @requests = []
    end
    def request(request)
      @requests << request
      @response
    end
  end

  def setup
    @env = {
      "GUARDLMS_SITE_URL" => "https://canvas.example.com/",
      "GUARDLMS_API_KEY" => "test-only-token"
    }
    @http = FakeHTTP.new
  end

  def connector
    GuardlmsCanvas::Connector.new(env: @env, http_factory: ->(uri) { @endpoint = uri; @http })
  end

  def payload
    connector.inventory(canvas: FakeCanvas, rails_version: "7.2.0", now: Time.at(100))
  end

  def test_collects_only_inventory_and_preserves_disabled_plugins
    data = payload
    assert_equal "https://canvas.example.com", data[:siteurl]
    assert_equal 100, data[:generatedtime]
    assert_equal "2026-10-21", data[:canvas][:version]
    assert_equal [{ id: "guardlms", version: "0.1.0", enabled: false }], data[:canvas][:plugins]
    refute_includes JSON.generate(data), "private"
  end

  def test_sends_authenticated_json_to_fixed_path_and_verifies_tls
    assert_equal 7, connector.push(payload)["website_id"]
    assert_equal "api.guardlms.com", @endpoint.host
    request = @http.requests.fetch(0)
    assert_equal "/api/externalpush/canvas", request.path
    assert_equal "Bearer test-only-token", request["Authorization"]
    assert_equal "https://canvas.example.com", JSON.parse(request.body)["siteurl"]
    assert_equal OpenSSL::SSL::VERIFY_PEER, @http.verify_mode
    assert @http.use_ssl
    assert_equal 0, @http.max_retries
  end

  def test_does_not_follow_redirects_or_print_remote_bodies
    @http = FakeHTTP.new("302", "secret remote text")
    error = assert_raises(GuardlmsCanvas::Error) { connector.push(payload) }
    assert_includes error.message, "302"
    refute_includes error.message, "secret"
    assert_equal 1, @http.requests.size
  end

  def test_credential_and_site_configuration_errors_are_actionable
    %w[401 403 422 429 500].each do |code|
      @http = FakeHTTP.new(code, "test-only-token")
      error = assert_raises(GuardlmsCanvas::Error) { connector.push(payload) }
      refute_includes error.message, "test-only-token"
    end
  end

  def test_rejects_non_https_or_credential_bearing_destinations_before_network
    ["http://api.example.com", "https://user:secret@api.example.com", "https://api.example.com/path",
     "https://api.example.com?token=secret", "https://api.example.com#fragment"].each do |url|
      @env["GUARDLMS_API_URL"] = url
      assert_raises(GuardlmsCanvas::Error) { connector.push(payload) }
    end
    assert_empty @http.requests
  end

  def test_requires_canonical_site_url_and_bound_key
    @env["GUARDLMS_SITE_URL"] = ""
    assert_raises(GuardlmsCanvas::Error) { payload }
    @env["GUARDLMS_SITE_URL"] = "https://canvas.example.com"
    @env["GUARDLMS_API_KEY"] = ""
    assert_raises(GuardlmsCanvas::Error) { connector.push(payload) }
    assert_empty @http.requests
  end

  def test_rejects_false_success_and_invalid_json
    ["<html>proxy login</html>", "{}", "[]", '{"data":{"website_id":"7"}}'].each do |body|
      @http = FakeHTTP.new("200", body)
      assert_raises(GuardlmsCanvas::Error) { connector.push(payload) }
    end
  end

  def test_network_errors_do_not_expose_secrets
    @http.define_singleton_method(:request) { |_request| raise SocketError, "secret hostname" }
    error = assert_raises(GuardlmsCanvas::Error) { connector.push(payload) }
    refute_includes error.message, "secret hostname"
  end

  def test_collection_failures_do_not_produce_partial_plugin_inventory
    plugin = FakeCanvas::Plugin
    original = plugin.method(:all)
    plugin.define_singleton_method(:all) { raise "database unavailable" }
    assert_raises(RuntimeError) { payload }
    assert_empty @http.requests
  ensure
    plugin.define_singleton_method(:all, original)
  end
end
