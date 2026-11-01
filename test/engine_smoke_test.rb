# frozen_string_literal: true
gem "minitest", "~> 5.0"
# Exercise actual Rails engine loading; Canvas is a minimal plugin-registry double.
require "tmpdir"
require "logger"
require "rails"
require "rails/engine"
require "rails/application"
require "minitest/autorun"

module Canvas
  class Plugin
    def self.register(id, tag, metadata)
      @registered = [id, tag, metadata]
    end
    def self.registered = @registered
  end
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "guardlms_canvas"

class EngineSmokeTest < Minitest::Test
  def test_engine_registers_plugin_and_loads_scheduled_task
    Dir.mktmpdir("guardlms-canvas-rails") do |root|
      app_class = Class.new(Rails::Application)
      app_class.config.root = root
      app_class.config.eager_load = false
      app_class.config.secret_key_base = "test" * 32
      app_class.config.logger = Logger.new(File::NULL)
      app_class.config.hosts.clear
      app = app_class.initialize!
      app.load_tasks
      assert_equal :guardlms, Canvas::Plugin.registered.fetch(0)
      assert_equal "0.1.0", Canvas::Plugin.registered.fetch(2).fetch(:version)
      assert Rake::Task.task_defined?("guardlms:push")
      assert_includes Rake::Task["guardlms:push"].prerequisites, "environment"
    end
  end
end
