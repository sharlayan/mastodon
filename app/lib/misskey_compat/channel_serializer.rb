# frozen_string_literal: true

class MisskeyCompat::ChannelSerializer
  include RoutingHelper

  def self.serialize(channel, current_account: nil, detailed: false)
    serialize_many([channel], current_account: current_account, detailed: detailed).first
  end

  def self.serialize_many(channels, current_account: nil, detailed: false)
    new(channels, current_account: current_account, detailed: detailed).serialize_all
  end

  def initialize(channels, current_account:, detailed:)
    @channels = channels.to_a
    @current_account = current_account
    @detailed = detailed
  end

  def serialize_all
    ActiveRecord::Associations::Preloader.new(records: @channels, associations: :banner_drive_file).call
    @channels.map { |channel| serialize(channel) }
  end

  private

  def serialize(channel)
    payload = {
      id: MisskeyCompat::MiId.encode(channel.id),
      createdAt: channel.created_at.iso8601,
      lastNotedAt: channel.last_noted_at&.iso8601,
      name: channel.name,
      description: channel.description,
      userId: MisskeyCompat::MiId.encode(channel.account_id),
      bannerUrl: banner_url(channel),
      bannerId: MisskeyCompat::MiId.encode(channel.banner_drive_file_id),
      pinnedNoteIds: MisskeyCompat::MiId.encode_many(channel.pinned_status_ids),
      color: channel.color,
      isArchived: channel.archived?,
      usersCount: channel.users_count,
      notesCount: channel.notes_count,
      isSensitive: channel.sensitive?,
      allowRenoteToExternal: channel.allow_renote_to_external?,
    }

    if @current_account
      payload.merge!(
        isFollowing: following_ids.include?(channel.id),
        isFavorited: favorite_ids.include?(channel.id),
        isMuting: muting_ids.include?(channel.id),
        hasUnreadNote: false
      )
    end

    payload[:pinnedNotes] = pinned_notes(channel) if @detailed
    payload
  end

  def banner_url(channel)
    file = channel.banner_drive_file
    return if file.nil? || file.file.blank?

    full_asset_url(file.file.url(:original))
  end

  def channel_ids
    @channel_ids ||= @channels.map(&:id)
  end

  def following_ids
    @following_ids ||= MisskeyChannelFollowing.where(account: @current_account, misskey_channel_id: channel_ids).pluck(:misskey_channel_id).to_set
  end

  def favorite_ids
    @favorite_ids ||= MisskeyChannelFavorite.where(account: @current_account, misskey_channel_id: channel_ids).pluck(:misskey_channel_id).to_set
  end

  def muting_ids
    @muting_ids ||= MisskeyChannelMuting.active.where(account: @current_account, misskey_channel_id: channel_ids).pluck(:misskey_channel_id).to_set
  end

  def pinned_notes(channel)
    statuses = pinned_statuses.values_at(*channel.pinned_status_ids).compact
    context = MisskeyCompat::SerializationContext.for(statuses, current_account: @current_account)
    statuses.select { |status| context.visible?(status) }.map { |status| MisskeyCompat::NoteSerializer.serialize(status, context: context) }
  end

  def pinned_statuses
    @pinned_statuses ||= Status.where(id: @channels.flat_map(&:pinned_status_ids).uniq).includes(:account).index_by(&:id)
  end
end
