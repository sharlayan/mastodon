# frozen_string_literal: true

module Sharlayan::FanOutOnWriteServiceExtensions
  def call(status, options = {})
    @misskey_channel_id = MisskeyChannelNote.where(status_id: status.id).pick(:misskey_channel_id)
    super
  end

  private

  def fan_out_to_local_recipients!
    return super if @misskey_channel_id.nil?

    unless @options[:skip_notifications]
      notify_quoted_account!
      notify_mentioned_accounts!
      notify_about_update! if update?
    end

    deliver_to_misskey_channel_followers!
    deliver_to_antennas!
    MisskeyCompat::Streaming.broadcast_anonymous_note(redis, ["channel:#{@misskey_channel_id}"], @status) unless update?
  end

  def broadcastable?
    @misskey_channel_id.nil? && super
  end

  def deliver_to_misskey_channel_followers!
    Account.local.joins(:user).merge(User.signed_in_recently)
      .where(id: MisskeyChannelFollowing.where(misskey_channel_id: @misskey_channel_id).select(:account_id))
      .select(:id).reorder(nil).find_in_batches do |followers|
        FeedInsertWorker.push_bulk(followers) do |follower|
          [@status.id, follower.id, 'home', { 'update' => update? }]
        end
      end
  end
end
