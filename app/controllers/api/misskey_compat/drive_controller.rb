# frozen_string_literal: true

class Api::MisskeyCompat::DriveController < Api::MisskeyCompat::BaseController
  before_action :require_user!

  def create
    return render_invalid_param('#/properties/file', 'file required') if params[:file].blank?

    media = current_account.media_attachments.create!(
      file: params[:file],
      thumbnail: params[:thumbnail],
      description: params[:comment].presence
    )

    render json: MisskeyCompat::DriveFileSerializer.serialize(media)
  rescue ActiveRecord::RecordInvalid, Mastodon::ValidationError => e
    render_error(e.to_s, 'INVALID_FILE', 400)
  end
end
