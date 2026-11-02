# frozen_string_literal: true
require "rbconfig"

module GuardlmsCanvas
  # Collect application-environment metadata, never hostnames, paths or credentials.
  module EnvironmentInventory
    OS_FIELDS = {"NAME" => :os_name, "ID" => :os_id, "VERSION_ID" => :os_version, "PRETTY_NAME" => :os_pretty}.freeze

    def self.collect(env: ENV, os_release_path: "/etc/os-release", arch: RbConfig::CONFIG["host_cpu"], database: nil)
      server = {arch: bounded(arch, 50)}.compact
      server[:os_family] = RUBY_PLATFORM.include?("linux") ? "Linux" : RbConfig::CONFIG["host_os"]
      if File.file?(os_release_path) && File.size(os_release_path) <= 16_384
        File.read(os_release_path).each_line do |line|
          key, value = line.strip.split("=", 2)
          field = OS_FIELDS[key]
          next unless field && value
          value = value[1...-1] if value.start_with?('"', "'") && value.end_with?(value[0])
          clean = bounded(value, field == :os_pretty ? 255 : field == :os_version ? 50 : 100)
          server[field] = clean if clean
        end
      end
      signature = bounded(env["GUARDLMS_WEBSERVER"], 255)
      server[:webserver] = signature if signature
      result = {server: server}
      version = database&.call
      # SHOW server_version may include a distribution suffix; send the version only.
      version = version.to_s[/\A\d+(?:\.\d+){0,3}/]
      result[:database] = {version: version} if version
      result
    rescue Errno::ENOENT, Errno::EACCES
      {server: server}
    end

    def self.postgres_version
      return unless defined?(::ActiveRecord::Base) && defined?(::Shard)
      Shard.default.activate do
        connection = ActiveRecord::Base.connection
        connection.select_value("SHOW server_version") if connection.adapter_name == "PostgreSQL"
      end
    rescue StandardError
      nil # Unavailable optional metadata must not prevent the complete plugin report.
    end

    def self.bounded(value, limit)
      text = value.to_s.strip
      text if !text.empty? && text.length <= limit && !text.match?(/[\x00-\x1f]/)
    end
  end
end
