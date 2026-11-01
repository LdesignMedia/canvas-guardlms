# frozen_string_literal: true
namespace :guardlms do
  desc "Push Canvas component inventory to GuardLMS (schedule daily on one node)"
  task push: :environment do
    require "guardlms_canvas"
    begin
      result = GuardlmsCanvas::Reporting.push(force: true)
      abort "GuardLMS is disabled, not connected, or a push is already running" unless result
      puts "GuardLMS inventory accepted: #{result.fetch('components_upserted')} components"
    rescue GuardlmsCanvas::Error => error
      abort error.message
    end
  end
end
