# frozen_string_literal: true

class UpdateMediaAttachmentsPermissionsService < BaseService
  def call(media_attachments_scope, direction)
    # Only s3 and filesystem storage systems support modifying permissions
    return unless %i(s3 filesystem).include?(Paperclip::Attachment.default_options[:storage])

    # Prevent useless S3 calls if ACLs are disabled
    return if Paperclip::Attachment.default_options[:storage] == :s3 && ENV['S3_PERMISSION'] == ''

    processed_records = Set.new

    media_attachments_scope.includes(:drive_file).find_each do |media_attachment|
      record = media_attachment.drive_pointer? ? media_attachment.drive_file : media_attachment
      next unless processed_records.add?([record.class.name, record.id])

      record.class.attachment_definitions.each_key do |attachment_name|
        attachment = record.public_send(attachment_name)
        styles     = MediaAttachment::DEFAULT_STYLES | attachment.styles.keys.map(&:to_sym)

        next if attachment.blank?

        styles.each do |style|
          case Paperclip::Attachment.default_options[:storage]
          when :s3
            acl = direction == :public ? Paperclip::Attachment.default_options[:s3_permissions] : 'private'

            begin
              attachment.s3_object(style).acl.put(acl: acl)
            rescue Aws::S3::Errors::NoSuchKey
              Rails.logger.warn "Tried to change acl on non-existent key #{attachment.s3_object(style).key}"
            rescue Aws::S3::Errors::NotImplemented => e
              Rails.logger.error "Error trying to change ACL on #{attachment.s3_object(style).key}: #{e.message}"
            end
          when :filesystem
            mask = direction == :public ? 0o666 : 0o600

            begin
              FileUtils.chmod(mask & ~File.umask, attachment.path(style)) unless attachment.path(style).nil?
            rescue Errno::ENOENT
              Rails.logger.warn "Tried to change permission on non-existent file #{attachment.path(style)}"
            end
          end

          CacheBusterWorker.perform_async(attachment.url(style)) if Rails.configuration.x.cache_buster.enabled
        end
      end
    end
  end
end
