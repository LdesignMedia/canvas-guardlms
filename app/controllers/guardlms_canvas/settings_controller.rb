# frozen_string_literal: true
module GuardlmsCanvas
  class SettingsController < ::ApplicationController
    before_action :require_guardlms_admin
    before_action :set_site_admin_context
    before_action :private_response
    rescue_from GuardlmsCanvas::Error, with: :configuration_error

    def show
      @settings = Store.read
      @config = Configuration.environment(@settings)
      @connection_status = Configuration.status(@settings)
      @expiry_warning = Configuration.expiry_warning(@settings)
      @dashboard_link = Configuration.dashboard_link(@settings)
      @destination_label = Configuration.destination_label(@settings)
      set_active_tab "plugins"
    end

    def save
      Configuration.save(params.permit(:site_url, :api_url, :dashboard_url, :api_key, :enabled, :daily_enabled).to_h.symbolize_keys)
      flash[:notice] = "GuardLMS settings saved."
      redirect_to "/plugins/guardlms/manage"
    end

    def connect
      if ENV["GUARDLMS_API_KEY"].present?
        raise Error, "The inventory key is managed by the server environment. Remove that override before using one-click connection."
      end
      redirect_to Connection.start(session, @current_user.id), allow_other_host: true
    end

    def callback
      Connection.complete(session, @current_user.id, params[:code], params[:state])
      begin
        Reporting.push(force: true)
        flash[:notice] = "Connected to GuardLMS. The first inventory was accepted."
      rescue Error
        flash[:notice] = "Connected to GuardLMS. The first inventory failed; the worker will retry. See connection status."
      end
      redirect_to "/plugins/guardlms/manage"
    end

    def push
      result = Reporting.push(force: true)
      flash[:notice] = result ? "GuardLMS accepted #{result.fetch('components_upserted')} components." : "Reporting is disabled, not connected, or a push is already running."
      redirect_to "/plugins/guardlms/manage"
    end

    def disconnect
      session.delete(:guardlms_connect)
      Connection.disconnect
      flash[:notice] = "Disconnected locally. Reporting is stopped. You can also revoke this site's key in GuardLMS."
      redirect_to "/plugins/guardlms/manage"
    end

    def preview
      payload = Connector.new(env: Configuration.environment(Store.read)).inventory(canvas: Canvas, rails_version: Rails.version)
      render json: payload
    end

    private

    def require_guardlms_admin
      require_site_admin_with_permission(:manage_site_settings)
    end

    def private_response
      response.headers["Cache-Control"] = "no-store"
      response.headers["Referrer-Policy"] = "no-referrer"
    end

    def configuration_error(error)
      flash[:error] = error.message
      redirect_to "/plugins/guardlms/manage"
    end
  end
end
