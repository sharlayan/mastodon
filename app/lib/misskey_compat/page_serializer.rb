# frozen_string_literal: true

class MisskeyCompat::PageSerializer
  def self.serialize(page, current_account: nil, include_content: true)
    new.serialize(page, current_account: current_account, include_content: include_content)
  end

  def serialize(page, current_account: nil, include_content: true)
    attached_media = include_content ? page.renderable_attached_media.includes(:drive_file).to_a : []
    media_by_id = attached_media.index_by { |media| media.id.to_s }
    eye_catching_media = page.eye_catching_media_attachment

    result = {
      id: MisskeyCompat::MiId.encode(page.id),
      createdAt: page.created_at.iso8601,
      updatedAt: page.updated_at.iso8601,
      userId: MisskeyCompat::MiId.encode(page.account_id),
      user: MisskeyCompat::UserSerializer.serialize(page.account, viewer: current_account),
      content: include_content ? serialize_blocks(page.renderable_content, media_by_id) : [],
      variables: [],
      title: page.title,
      name: page.name,
      summary: page.summary,
      hideTitleWhenPinned: page.hide_title_when_pinned?,
      alignCenter: page.align_center?,
      font: page.font,
      script: '',
      eyeCatchingImageId: serialize_media_id(eye_catching_media),
      eyeCatchingImage: eye_catching_media && MisskeyCompat::DriveFileSerializer.serialize(eye_catching_media),
      attachedFiles: attached_media.map { |media| MisskeyCompat::DriveFileSerializer.serialize(media) },
      likedCount: page.likes_count,
    }
    result[:isLiked] = page.liked_by?(current_account) if current_account && include_content
    result
  end

  private

  def serialize_blocks(blocks, media_by_id)
    Array(blocks).filter_map do |source|
      next if source['type'] == 'youtube'

      block = source.deep_dup
      block.delete('spoiler')
      block['fileId'] = serialize_media_id(media_by_id[block['fileId'].to_s]) if block['type'] == 'image' && block['fileId'].present?
      block['note'] = MisskeyCompat::MiId.encode(block['note']) if block['type'] == 'note' && block['note'].present?
      block['children'] = serialize_blocks(block['children'], media_by_id) if block['children'].is_a?(Array)
      block
    end
  end

  def serialize_media_id(media)
    return nil if media.nil?

    MisskeyCompat::MiId.encode(media.drive_pointer? ? media.drive_file_id : media.id)
  end
end
