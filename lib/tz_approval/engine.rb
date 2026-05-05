# frozen_string_literal: true

module ::TzApproval
  class Engine < ::Rails::Engine
    engine_name TzApproval::PLUGIN_NAME
    isolate_namespace TzApproval
  end
end
