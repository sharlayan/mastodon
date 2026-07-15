# frozen_string_literal: true

class DriveMediaController < ApplicationController
  include RoutingHelper

  skip_before_action :require_functional!, raise: false

  before_action :set_media_attachment

  def show
    attachment, resolved_style = resolve_attachment

    if source_record.unknown?
      serve_as_download(attachment, resolved_style)
    elsif local_storage?
      serve_from_disk(attachment, resolved_style)
    else
      serve_with_redirect(attachment, resolved_style)
    end
  end

  private

  def local_storage?
    Paperclip::Attachment.default_options[:storage] == :filesystem
  end

  def set_media_attachment
    @media_attachment = MediaAttachment.find_by!(drive_access_key: params[:id])
  rescue ActiveRecord::RecordNotFound
    not_found
  end

  def source_record
    @source_record ||= @media_attachment.drive_file || @media_attachment
  end

  def requested_style
    params[:style] == 'small' ? :small : :original
  end

  def resolve_attachment
    if requested_style == :small
      if source_record.file.styles.key?(:small)
        [source_record.file, :small]
      elsif source_record.thumbnail.present?
        [source_record.thumbnail, :original]
      else
        [source_record.file, :original]
      end
    else
      [source_record.file, :original]
    end
  end

  def private_bucket?
    ENV['S3_ENABLED'] == 'true' && ENV['S3_PERMISSION'] == ''
  end

  def serve_from_disk(attachment, style)
    path = attachment.path(style)

    return not_found if path.blank? || !File.exist?(path)

    content_type = resolved_content_type(attachment, style)
    filename = source_record.respond_to?(:display_name) ? source_record.display_name.to_s : source_record.file_file_name.to_s

    return send_file(path, type: content_type, disposition: 'inline', filename: filename) if sendfile_header?

    status, headers, body = Rack::Files.new(File.dirname(path)).serving(request, path)

    headers.each { |header, value| response.headers[header] = value }

    response.headers['Content-Type'] = content_type
    response.headers['Content-Disposition'] = ActionDispatch::Http::ContentDisposition.format(disposition: 'inline', filename: filename)
    response.headers['Cache-Control'] = 'public, max-age=31536000, immutable'
    self.status = status
    self.response_body = body
  end

  def serve_as_download(attachment, style)
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['Content-Security-Policy'] = "default-src 'none'; sandbox"

    send_data download_data(attachment, style), type: attachment.instance_read(:content_type), disposition: 'attachment', filename: source_record.file_file_name
  end

  def resolved_content_type(attachment, style)
    definition = attachment.styles[style]
    return attachment.instance_read(:content_type) if definition.nil?

    definition[:content_type].presence || Rack::Mime.mime_type(".#{definition[:format]}", attachment.instance_read(:content_type))
  end

  def download_data(attachment, style)
    return File.binread(attachment.path(style)) if local_storage?

    adapter = Paperclip.io_adapters.for(attachment)
    adapter.rewind
    adapter.read
  end

  def sendfile_header?
    Rails.configuration.action_dispatch.x_sendfile_header.present?
  end

  def serve_with_redirect(attachment, style)
    url = if private_bucket? && attachment.respond_to?(:expiring_url)
            attachment.expiring_url(3600, style)
          else
            attachment.url(style)
          end

    return not_found if url.blank?

    redirect_to full_asset_url(url), allow_other_host: true
  end
end
