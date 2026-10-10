# frozen_string_literal: true

module Hello
  module Api
    # GET /api/hello/greetings — listed with the plugin in /api/manifest.
    class GreetingsController < ::Api::BaseController
      include PluginGated
      plugin :hello
      enforce_authorization
      requires_capability "hello:read", only: :index

      def index
        @greetings = Greeting.newest_first.limit(50)
      end
    end
  end
end
