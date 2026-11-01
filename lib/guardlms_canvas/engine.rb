# frozen_string_literal: true
module GuardlmsCanvas
  module PluginScreen
    def show
      if params[:id] == "guardlms" && request.format.html?
        redirect_to "/plugins/guardlms/manage"
      else
        super
      end
    end

    def update
      # Canvas's generic plugin updater accepts arbitrary nested settings. All
      # GuardLMS writes must use our allowlisted, generation-aware controller.
      params[:id] == "guardlms" ? head(:method_not_allowed) : super
    end
  end

  module OwnershipTag
    def guardlms_ownership_tag
      settings = GuardlmsCanvas::Store.read
      return if settings[:disabled] || !GuardlmsCanvas::Configuration.connected?(settings)
      token = settings[:verification_token]
      return unless token.to_s.match?(/\A[a-zA-Z0-9_-]{16,255}\z/)
      (@content_for_head ||= []) << helpers.tag.meta(name: "guardlms-verification", content: token)
    end
  end

  class Engine < ::Rails::Engine
    # Routes extend the Canvas application so its layout keeps host route helpers.

    initializer "guardlms_canvas.routes" do |app|
      app.routes.prepend do
        get "/plugins/guardlms/manage", to: "guardlms_canvas/settings#show"
        get "/plugins/guardlms/preview", to: "guardlms_canvas/settings#preview"
        get "/plugins/guardlms/callback", to: "guardlms_canvas/settings#callback"
        %w[save connect push disconnect].each do |action|
          post "/plugins/guardlms/#{action}", to: "guardlms_canvas/settings##{action}"
        end
      end
    end

    initializer "guardlms_canvas.parameter_filter" do |app|
      app.config.filter_parameters += [:api_key, :code, :state]
    end

    config.to_prepare do
      Canvas::Plugin.register(:guardlms, nil, {
        name: "GuardLMS", description: "Connect this Canvas installation to GuardLMS for daily inventory monitoring.",
        version: "0.2.0", website: "https://guardlms.com", author: "Ldesign Media",
        settings_partial: "guardlms_canvas/settings/link", encrypted_settings: [:api_key], settings: {}
      })
      if defined?(::PluginsController)
        ::PluginsController.prepend(PluginScreen) unless ::PluginsController < PluginScreen
      end
      if defined?(::ApplicationController) && !(::ApplicationController < OwnershipTag)
        ::ApplicationController.include(OwnershipTag)
        ::ApplicationController.before_action(:guardlms_ownership_tag)
      end
    end

    config.after_initialize do
      if defined?(Delayed::Periodic) && !Delayed::Periodic.scheduled.key?("GuardlmsCanvas::Reporting.run")
        Delayed::Periodic.cron("GuardlmsCanvas::Reporting.run", "*/5 * * * *") do
          GuardlmsCanvas::Reporting.run
        end
      end
    end
  end
end
