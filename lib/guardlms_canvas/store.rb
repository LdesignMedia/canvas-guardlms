# frozen_string_literal: true
module GuardlmsCanvas
  # All connection state belongs to the installation's default shard.
  module Store
    def self.read
      Shard.default.activate do
        record = PluginSetting.find_by_name("guardlms")
        record ? record.settings.to_h.symbolize_keys.merge(disabled: record.disabled) : { disabled: true }
      end
    end

    def self.update
      Shard.default.activate do
        PluginSetting.transaction do
          record = PluginSetting.find_or_create_by!(name: "guardlms") do |setting|
            setting.settings = {}
            setting.disabled = true
          end
          record.lock!
          data = record.settings.to_h.symbolize_keys.merge(disabled: record.disabled)
          result = yield data
          record.disabled = data.delete(:disabled)
          record.settings = data
          record.save!
          result
        end
      end
    end
  end
end
