# frozen_string_literal: true

class MisskeyCompat::GalleryPostSerializer
  def self.serialize(post, current_account: nil)
    serialize_many([post], current_account: current_account).first
  end

  def self.serialize_many(posts, current_account: nil)
    new(posts, current_account: current_account).serialize_all
  end

  def initialize(posts, current_account: nil)
    @posts = Array(posts).compact
    @current_account = current_account
  end

  def serialize_all
    preload
    @posts.map { |post| serialize(post) }
  end

  private

  def preload
    ids = @posts.flat_map(&:media_attachment_ids).uniq
    @media_by_id = ids.empty? ? {} : MediaAttachment.where(id: ids).includes(:status, drive_file: :custom_name).index_by(&:id)
    @liked_ids = if @current_account && @posts.any?
                   MisskeyGalleryLike.where(account_id: @current_account.id, misskey_gallery_post_id: @posts.map(&:id)).pluck(:misskey_gallery_post_id).to_set
                 else
                   Set.new
                 end
    @users = {}
  end

  def serialize(post)
    media = post.media_attachment_ids.filter_map { |id| @media_by_id[id] if @media_by_id[id]&.account_id == post.account_id }

    result = {
      id: MisskeyCompat::MiId.encode(post.id),
      createdAt: post.created_at.iso8601,
      updatedAt: post.updated_at.iso8601,
      userId: MisskeyCompat::MiId.encode(post.account_id),
      user: @users[post.account_id] ||= MisskeyCompat::UserSerializer.serialize(post.account, viewer: @current_account),
      title: post.title,
      description: post.description,
      fileIds: media.map { |item| MisskeyCompat::MiId.encode(item.drive_pointer? ? item.drive_file_id : item.id) },
      files: media.map { |item| MisskeyCompat::DriveFileSerializer.serialize(item) },
      isSensitive: post.sensitive?,
      likedCount: post.likes_count,
    }
    result[:isLiked] = @liked_ids.include?(post.id) if @current_account
    result
  end
end
