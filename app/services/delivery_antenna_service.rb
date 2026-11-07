# frozen_string_literal: true

class DeliveryAntennaService
  def call(status, update, mode: :home)
    return unless Setting.antenna_enabled

    @status = status
    @update = update
    @mode   = mode
    @target = status.reblog? ? status.reblog : status

    return if @target.nil?

    deliver!
  end

  private

  def deliver!
    candidates = Antenna.matching(@status).to_a
    @candidate_account_ids = candidates.map(&:account_id).uniq
    antennas = candidates.select { |antenna| deliverable?(antenna) }

    return if antennas.empty?

    FeedInsertWorker.push_bulk(antennas) do |antenna|
      [@status.id, antenna.id, 'antenna', { 'update' => @update }]
    end
  end

  def deliverable?(antenna)
    return false unless antenna.account.user&.signed_in_recently?
    return false if @status.reblog? && antenna.ignore_reblog?
    return false if antenna.with_media_only? && !@target.with_media?
    return false unless silenced_authors_followed_by?(antenna)

    visible_to?(antenna)
  end

  def silenced_authors_followed_by?(antenna)
    silenced_author_ids.all? do |author_id|
      author_id == antenna.account_id || silenced_author_follows.include?([antenna.account_id, author_id])
    end
  end

  def silenced_author_ids
    @silenced_author_ids ||= [@status.account, @target.account].uniq.select(&:silenced?).map(&:id)
  end

  def silenced_author_follows
    @silenced_author_follows ||= Follow.where(account_id: @candidate_account_ids, target_account_id: silenced_author_ids).pluck(:account_id, :target_account_id).to_set
  end

  def visible_to?(antenna)
    if @status.public_visibility? || @status.unlisted_visibility?
      true
    elsif @status.private_visibility?
      antenna.account_id == @status.account_id || follower_account_ids.include?(antenna.account_id)
    else
      false
    end
  end

  def follower_account_ids
    @follower_account_ids ||= Follow.where(target_account_id: @status.account_id, account_id: @candidate_account_ids).pluck(:account_id).to_set
  end
end
