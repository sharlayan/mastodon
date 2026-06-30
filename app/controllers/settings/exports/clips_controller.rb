# frozen_string_literal: true

module Settings
  module Exports
    class ClipsController < BaseController
      include Settings::ExportControllerConcern

      before_action :require_feature_enabled!

      def index
        send_export_file
      end

      private

      def export_data
        @export.to_clips_json
      end

      def require_feature_enabled!
        not_found unless Setting.clips_enabled
      end
    end
  end
end
