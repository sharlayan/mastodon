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
    antennas = Antenna.matching(@status).select { |antenna| deliverable?(antenna) }

    return if antennas.empty?

    FeedInsertWorker.push_bulk(antennas) do |antenna|
      [@status.id, antenna.id, 'antenna', { 'update' => @update }]
    end
  end

  def deliverable?(antenna)
    return false unless antenna.account.user&.signed_in_recently?
    return false if @status.reblog? && antenna.ignore_reblog?
    return false if antenna.with_media_only? && !@target.with_media?

    visible_to?(antenna)
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
    @follower_account_ids ||= @status.account.followers.pluck(:id).to_set
  end
end
