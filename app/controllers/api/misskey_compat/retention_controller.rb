# frozen_string_literal: true

class Api::MisskeyCompat::RetentionController < Api::MisskeyCompat::BaseController
  MAX_RECORDS = 30

  def index
    return unless object_body!
    return if rate_limited?(:misskey_compat_api)

    records = MisskeyRetentionAggregation.order(id: :desc).limit(MAX_RECORDS)

    render json: records.map { |record| serialize(record) }
  end

  private

  def serialize(record)
    {
      createdAt: record.created_at.iso8601,
      users: record.users_count,
      data: record.data,
    }
  end
end
