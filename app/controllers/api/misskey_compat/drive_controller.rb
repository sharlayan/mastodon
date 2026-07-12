# frozen_string_literal: true

class Api::MisskeyCompat::DriveController < Api::MisskeyCompat::BaseController
  requires_write_scope :create

  before_action :require_user!, only: [:create, :attached_notes]

  def unavailable
    render_error('Drive is not available on this server', 'UNAVAILABLE', 400)
  end

  def attached_notes
    media = current_account.media_attachments.find_by(id: params[:fileId])
    return render_error('No such file', 'NO_SUCH_FILE', 404) if media.nil?

    status = media.status
    statuses = status && StatusPolicy.new(current_account, status).show? ? [status] : []
    Status.preload_cacheable_associations(statuses)
    context = MisskeyCompat::SerializationContext.for(statuses, current_account: current_account)

    render json: statuses.map { |note| MisskeyCompat::NoteSerializer.serialize(note, context: context) }
  end

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
