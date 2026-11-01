# frozen_string_literal: true
module GuardlmsCanvas
  class Engine < ::Rails::Engine
    isolate_namespace GuardlmsCanvas

    config.to_prepare do
      Canvas::Plugin.register(:guardlms, nil, {
        name: "GuardLMS",
        description: "Reports installed Canvas components to GuardLMS via the guardlms:push task.",
        version: "0.1.0",
        website: "https://guardlms.com",
        author: "Ldesign Media"
      })
    end
  end
end
