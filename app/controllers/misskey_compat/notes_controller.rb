# frozen_string_literal: true

module MisskeyCompat
  class NotesController < ApplicationController
    skip_before_action :require_functional!

    before_action :require_misskey_compat_enabled!

    def show
      status = find_status

      return not_found if status.nil?

      redirect_to ActivityPub::TagManager.instance.url_for(status), allow_other_host: true, status: 302
    end

    private

    def find_status
      id = MisskeyCompat::MiId.decode(params[:id].to_s)
      return nil unless id.to_s.match?(/\A\d+\z/)

      status = Status.find_by(id: id)
      return nil if status.nil? || !status.distributable?

      status
    end

    def require_misskey_compat_enabled!
      not_found unless Setting.misskey_compat_enabled
    end
  end
end
