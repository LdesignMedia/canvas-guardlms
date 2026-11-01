# frozen_string_literal: true
namespace :guardlms do
  desc "Push Canvas component inventory to GuardLMS (schedule daily on one node)"
  task push: :environment do
    require "guardlms_canvas/connector"
    begin
      connector = GuardlmsCanvas::Connector.new
      result = connector.push(connector.inventory(canvas: Canvas, rails_version: Rails.version))
      puts "GuardLMS inventory accepted: #{result.fetch('components_upserted')} components"
    rescue GuardlmsCanvas::Error => error
      abort error.message
    end
  end
end
