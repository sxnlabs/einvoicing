# frozen_string_literal: true

module Einvoicing
  module Rails
    # Rails engine entry point. Automatically extends ActiveRecord::Base with
    # the Invoiceable concern when loaded inside a Rails application.
    class Engine < ::Rails::Engine
      isolate_namespace Einvoicing

      initializer "einvoicing.active_record" do
        ActiveSupport.on_load(:active_record) do
          # Models opt-in via `include Einvoicing::Invoiceable`
        end
      end
    end
  end
end
