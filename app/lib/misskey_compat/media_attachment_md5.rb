# frozen_string_literal: true

class MisskeyCompat::MediaAttachmentMd5
  def self.for(media)
    new(media).call
  end

  def initialize(media)
    @media = media
  end

  def call
    return if @media.nil? || @media.file.blank?
    return unless local_filesystem?

    path = @media.file.path(:original)
    return if path.blank? || !File.exist?(path)

    digest = Digest::MD5.file(path).hexdigest
    persist(digest)
    digest
  rescue SystemCallError
    nil
  end

  private

  def local_filesystem?
    @media.file.options[:storage].to_sym == :filesystem
  end

  def persist(digest)
    return unless @media.persisted?

    meta = @media.file_meta.is_a?(Hash) ? @media.file_meta.dup : {}
    return if meta['md5'] == digest

    meta['md5'] = digest
    @media.update_column(:file_meta, meta)
  end
end
