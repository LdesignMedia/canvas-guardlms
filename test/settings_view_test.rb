# frozen_string_literal: true
gem "minitest", "~> 5.0"
require "minitest/autorun"
require "action_view"
require_relative "../lib/guardlms_canvas/connector"
require_relative "../lib/guardlms_canvas/configuration"

class SettingsViewTest < Minitest::Test
  def render_settings(overrides = {})
    settings = {
      site_url: "https://canvas.example.com", api_key_dec: "private-key",
      api_url: "https://api-staging.guardlms.com", dashboard_url: "https://dashboard-staging.guardlms.com",
      website_id: 35, daily_enabled: true, next_attempt_at: Time.utc(2030, 1, 2).to_i,
      failure_count: 2, expires_at: (Time.now + 15 * 86_400).iso8601
    }.merge(overrides)
    lookup = ActionView::LookupContext.new([File.expand_path("../app/views", __dir__)])
    assigns = {
      settings: settings, config: GuardlmsCanvas::Configuration.environment(settings, {}),
      connection_status: GuardlmsCanvas::Configuration.status(settings, {}),
      expiry_warning: GuardlmsCanvas::Configuration.expiry_warning(settings),
      dashboard_link: GuardlmsCanvas::Configuration.dashboard_link(settings, {}),
      destination_label: GuardlmsCanvas::Configuration.destination_label(settings, {})
    }
    ActionView::Base.with_empty_template_cache.new(lookup, assigns, nil).render(template: "guardlms_canvas/settings/show")
  end

  def test_connected_staging_view_links_to_its_website_and_shows_retry_and_expiry
    html = render_settings
    assert_includes html, 'href="https://dashboard-staging.guardlms.com/websites/35"'
    assert_includes html, "Open dashboard"
    assert_includes html, "Reconnect to GuardLMS"
    assert_includes html, "Staging"
    assert_includes html, "Next retry"
    assert_includes html, "2030-01-02 00:00 UTC"
    assert_includes html, "Reconnect before expiry"
    refute_includes html, "private-key"
  end

  def test_disconnected_view_does_not_offer_an_invalid_dashboard_link_or_schedule
    html = render_settings(api_key_dec: nil, disabled: true, managed: true, dashboard_url: "javascript:alert(1)", expires_at: nil)
    refute_includes html, "Open dashboard"
    refute_includes html, "Reconnect to GuardLMS"
    assert_includes html, "Connect to GuardLMS"
    assert_includes html, "Automatic reporting is off"
    refute_includes html, "2030-01-02 00:00 UTC"
  end
end
