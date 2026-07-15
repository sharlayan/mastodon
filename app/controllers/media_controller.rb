# frozen_string_literal: true

class MediaController < ApplicationController
  include Authorization
  include RoleplayModeHelper
  include RoutingHelper

  skip_before_action :require_functional!, unless: :limited_federation_mode?

  before_action :authenticate_user!, if: :limited_federation_mode?
  before_action :set_media_attachment
  before_action :verify_permitted_status!
  before_action :check_playable, only: :player
  before_action :allow_iframing, only: :player

  content_security_policy only: :player do |policy|
    policy.frame_ancestors(false)
  end

  def show
    if permitted_status&.rp_hidden? && !@media_attachment.drive_pointer?
      serve_hidden_media
    else
      target = @media_attachment.drive_pointer? ? full_media_attachment_url(@media_attachment) : @media_attachment.file.url(:original)
      redirect_to target, allow_other_host: true
    end
  end

  def player; end

  private

  def permitted_status
    return @permitted_status if defined?(@permitted_status)

    scope = roleplay_mode? ? Status.with_rp_hidden : Status
    @permitted_status = scope.find_by(id: @media_attachment.status_id)
  end

  def serve_hidden_media
    case Paperclip::Attachment.default_options[:storage]
    when :s3
      redirect_to @media_attachment.file.expiring_url(60, :original)
    else
      send_file @media_attachment.file.path(:original), type: @media_attachment.file_content_type, disposition: 'inline'
    end
  end

  def set_media_attachment
    @media_attachment = MediaAttachment.local.attached.identified(params[:id])
  end

  def verify_permitted_status!
    authorize permitted_status, :show?
  rescue ActiveRecord::RecordNotFound, Mastodon::NotPermittedError
    not_found
  end

  def check_playable
    not_found unless @media_attachment.larger_media_format?
  end

  def allow_iframing
    response.headers.delete('X-Frame-Options')
  end
end
