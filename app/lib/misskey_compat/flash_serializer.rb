# frozen_string_literal: true

class MisskeyCompat::FlashSerializer
  def self.serialize(flash, current_account: nil)
    serialize_many([flash], current_account: current_account).first
  end

  def self.serialize_many(flashes, current_account: nil)
    new(flashes, current_account: current_account).serialize_all
  end

  def initialize(flashes, current_account: nil)
    @flashes = Array(flashes).compact
    @current_account = current_account
  end

  def serialize_all
    @users = {}
    @liked_ids = if @current_account && @flashes.any?
                   MisskeyFlashLike.where(account_id: @current_account.id, misskey_flash_id: @flashes.map(&:id)).pluck(:misskey_flash_id).to_set
                 else
                   Set.new
                 end
    @flashes.map { |flash| serialize(flash) }
  end

  private

  def serialize(flash)
    result = {
      id: MisskeyCompat::MiId.encode(flash.id),
      createdAt: flash.created_at.iso8601,
      updatedAt: flash.updated_at.iso8601,
      userId: MisskeyCompat::MiId.encode(flash.account_id),
      user: @users[flash.account_id] ||= MisskeyCompat::UserSerializer.serialize(flash.account, viewer: @current_account),
      title: flash.title,
      summary: flash.summary,
      script: flash.script,
      visibility: flash.visibility,
      likedCount: flash.likes_count,
    }
    result[:isLiked] = @liked_ids.include?(flash.id) if @current_account
    result
  end
end
