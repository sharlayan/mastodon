# frozen_string_literal: true

class MediaProxyController < ApplicationController
  include RoutingHelper
  include Authorization
  include Redisable
  include Lockable

  skip_before_action :require_functional!

  before_action :authenticate_user!, if: -> { limited_federation_mode? && params[:chat_token].blank? && !federated_chat_request? }
  before_action :set_media_attachment

  rescue_from ActiveRecord::RecordInvalid, Mastodon::NotPermittedError, Mastodon::UnexpectedResponseError, with: :not_found
  rescue_from(*Mastodon::HTTP_CONNECTION_ERRORS, with: :internal_server_error)

  def show
    if @media_attachment.drive_pointer?
      redirect_to full_media_attachment_url(@media_attachment, preview_requested? ? :small : :original)
      return
    end

    if @media_attachment.needs_redownload? && !reject_media?
      with_redis_lock("media_download:#{params[:id]}") do
        @media_attachment.reload # Reload once we have acquired a lock, in case the file was downloaded in the meantime
        redownload! if @media_attachment.needs_redownload?
      end
    end

    # The address with this token only stays the same for a moment, and only this browser was given it. Without this,
    # opening a conversation again asks for every picture again, however many times the same address was given out.
    expires_in Sharlayan::ChatMediaToken::STABLE_FOR, public: false if @viewer_holds_chat_token

    if requires_file_streaming?
      send_file(media_attachment_file.path, type: media_attachment_file.instance_read(:content_type), disposition: 'inline')
    else
      redirect_to media_attachment_file_path, allow_other_host: true
    end
  end

  private

  def federated_chat_request?
    return false if params[:token].blank?

    media_attachment = MediaAttachment.find_by(id: params[:id])
    media_attachment.present? && media_attachment.chat_attachment? && Sharlayan::ChatFederation::MediaToken.valid?(params[:token], media_attachment)
  end

  def set_media_attachment
    @media_attachment = MediaAttachment.attached.find(params[:id])
    if params[:chat_token].present?
      viewer = Sharlayan::ChatMediaToken.viewer(params[:chat_token], @media_attachment)
      allowed = Setting.chat_enabled && viewer.present? && @media_attachment.chat_attachment? &&
                MediaAttachmentPolicy.new(viewer, @media_attachment).download?
      @viewer_holds_chat_token = allowed
      return if allowed
      # A token expires while a conversation stays open, and only a session can stand in for it.
      return head(404) unless user_signed_in?
    end

    if @media_attachment.chat_attachment? && Sharlayan::ChatFederation::MediaToken.valid?(params[:token], @media_attachment)
      head 404 unless Setting.chat_enabled && Setting.chat_federation_enabled
      return
    end

    authorize @media_attachment, :download?
  end

  def redownload!
    @media_attachment.download_file!
    @media_attachment.download_thumbnail!
    @media_attachment.created_at = Time.now.utc
    @media_attachment.save!
  end

  def attachment_style
    if @media_attachment.thumbnail.blank? && preview_requested?
      :small
    else
      :original
    end
  end

  def reject_media?
    @media_attachment.account.remote? && DomainBlock.reject_media?(@media_attachment.account.domain)
  end

  def media_attachment_file_path
    if @media_attachment.on_hold?
      expiring_asset_url(media_attachment_file, 10.minutes)
    else
      full_asset_url(media_attachment_file.url(attachment_style))
    end
  end

  def media_attachment_file
    if @media_attachment.thumbnail.present? && preview_requested?
      @media_attachment.thumbnail
    else
      @media_attachment.file
    end
  end

  def preview_requested?
    request.path.end_with?('/small')
  end

  def requires_file_streaming?
    Paperclip::Attachment.default_options[:storage] == :filesystem && @media_attachment.on_hold?
  end
end
