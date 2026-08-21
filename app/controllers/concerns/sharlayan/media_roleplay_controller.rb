# frozen_string_literal: true

module Sharlayan::MediaRoleplayController
  include RoleplayModeHelper

  def show
    return super unless roleplay_mode?
    return super unless permitted_status&.rp_hidden? && !@media_attachment.drive_pointer?

    serve_roleplay_hidden_media
  end

  private

  def permitted_status
    return @permitted_status if defined?(@permitted_status)

    scope = roleplay_mode? ? Status.with_rp_hidden : Status
    @permitted_status = scope.find_by(id: @media_attachment.status_id)
  end

  def verify_permitted_status!
    authorize permitted_status, :show?
  rescue ActiveRecord::RecordNotFound, Mastodon::NotPermittedError
    not_found
  end

  def serve_roleplay_hidden_media
    case Paperclip::Attachment.default_options[:storage]
    when :s3
      redirect_to @media_attachment.file.expiring_url(60, :original)
    else
      send_file @media_attachment.file.path(:original), type: @media_attachment.file_content_type, disposition: 'inline'
    end
  end
end
