# frozen_string_literal: true

class MarkStatusesReadService < BaseService
  include Redisable

  def initialize(redis: nil)
    super()
    @redis = redis
  end

  def call(account, status_ids)
    @account = account
    @read_at = Time.current
    @statuses = eligible_statuses(status_ids).to_a
    return if @statuses.empty?

    inserted = StatusReadReceipt.insert_all(receipt_rows, unique_by: [:status_id, :account_id], returning: [:status_id])
    publish(inserted.rows.flatten.map(&:to_i))
  end

  private

  def redis
    @redis || super
  end

  def eligible_statuses(status_ids)
    Status.joins(:account, :active_mentions)
      .merge(Account.local)
      .where(id: status_ids, visibility: :direct, mentions: { account_id: @account.id })
      .where.not(account_id: @account.id)
      .select(:id, :account_id)
      .distinct
  end

  def receipt_rows
    @statuses.map { |status| { status_id: status.id, account_id: @account.id, read_at: @read_at } }
  end

  def publish(status_ids)
    return if status_ids.empty?

    author_ids = @statuses.filter_map { |status| status.account_id if status_ids.include?(status.id) }.uniq
    payload = { account_id: @account.id.to_s, status_ids: status_ids.map(&:to_s), read_at: @read_at.iso8601(3) }.to_json
    message = { event: :'conversation.read', payload: payload }.to_json
    author_ids.each { |account_id| redis.publish("timeline:direct:#{account_id}", message) }
  end
end
