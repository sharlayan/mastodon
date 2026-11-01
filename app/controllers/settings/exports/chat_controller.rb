# frozen_string_literal: true

module Settings
  module Exports
    class ChatController < BaseController
      include Settings::ExportControllerConcern

      before_action :require_feature_enabled!

      def index
        send_export_file
      end

      private

      def export_data
        @export.to_chat_json
      end

      def require_feature_enabled!
        not_found unless Setting.chat_enabled
      end
    end
  end
end
