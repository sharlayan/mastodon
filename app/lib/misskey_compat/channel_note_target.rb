# frozen_string_literal: true

class MisskeyCompat::ChannelNoteTarget
  class NoSuchChannelError < StandardError; end
  class RenoteOutsideChannelError < StandardError; end

  def self.resolve(channel_id:, reply:, renote:)
    new(channel_id, reply, renote).resolve
  end

  def initialize(channel_id, reply, renote)
    @channel_id = channel_id
    @reply = reply
    @renote = renote
  end

  def resolve
    requested = requested_channel
    check_renote!(requested)
    return channel_of(@reply) if @reply

    requested
  end

  private

  def requested_channel
    return if @channel_id.blank?

    channel = MisskeyChannel.unarchived.find_by(id: @channel_id) if @channel_id.to_s.match?(/\A[1-9][0-9]{0,18}\z/)
    raise NoSuchChannelError if channel.nil?

    channel
  end

  def check_renote!(requested)
    return if @renote.nil?

    renote_channel_id = MisskeyChannelNote.where(status_id: @renote.id).pick(:misskey_channel_id)
    return if renote_channel_id.nil? || renote_channel_id == requested&.id

    renote_channel = MisskeyChannel.find_by(id: renote_channel_id)
    raise NoSuchChannelError if renote_channel.nil?
    raise RenoteOutsideChannelError unless renote_channel.allow_renote_to_external?
  end

  def channel_of(status)
    MisskeyChannel.joins(:channel_notes).find_by(misskey_channel_notes: { status_id: status.id })
  end
end
