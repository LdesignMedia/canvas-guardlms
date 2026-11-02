# frozen_string_literal: true
gem "minitest", "~> 5.0"
require "minitest/autorun"
require "tmpdir"
require_relative "../lib/guardlms_canvas/environment_inventory"

class EnvironmentInventoryTest < Minitest::Test
  def test_reports_only_allowlisted_environment_metadata_and_actual_database_version
    Dir.mktmpdir do |dir|
      path = File.join(dir, "os-release")
      File.write(path, "NAME=\"Ubuntu\"\nID=ubuntu\nVERSION_ID=\"24.04\"\nPRETTY_NAME=\"Ubuntu 24.04 LTS\"\nPASSWORD=secret\n")
      data = GuardlmsCanvas::EnvironmentInventory.collect(env: {"GUARDLMS_WEBSERVER" => "nginx/1.24.0", "HOSTNAME" => "private-host", "PASSWORD" => "secret"}, os_release_path: path, arch: "x86_64", database: -> { "14.18 (Ubuntu 14.18-1)" })
      assert_equal "Ubuntu", data[:server][:os_name]
      assert_equal "24.04", data[:server][:os_version]
      assert_equal "ubuntu", data[:server][:os_id]
      assert_equal "x86_64", data[:server][:arch]
      assert_equal "nginx/1.24.0", data[:server][:webserver]
      assert_equal({version: "14.18"}, data[:database])
      refute_includes data.inspect, "secret"
      refute_includes data.inspect, "private-host"
      refute_includes data.inspect, dir
    end
  end

  def test_missing_or_oversized_os_file_and_unknown_database_are_optional
    Dir.mktmpdir do |dir|
      path = File.join(dir, "os-release")
      data = GuardlmsCanvas::EnvironmentInventory.collect(env: {}, os_release_path: path, database: -> { nil })
      refute data.key?(:database)
      refute data[:server].key?(:webserver)
      File.write(path, "NAME=" + "x" * 16_384)
      data = GuardlmsCanvas::EnvironmentInventory.collect(env: {"GUARDLMS_WEBSERVER" => "bad\nheader"}, os_release_path: path)
      refute data[:server].key?(:os_name)
      refute data[:server].key?(:webserver)
    end
  end
end
