# frozen_string_literal: true

class Api::V1::Drive::BaseController < Api::BaseController
  include Redisable

  before_action :require_feature_enabled!
  before_action :require_user!

  private

  def broadcast_drive_file(drive_file, type)
    MisskeyCompat::Streaming.broadcast_drive_file(redis, current_account, drive_file, type)
  end

  def broadcast_drive_folder(drive_folder, type)
    MisskeyCompat::Streaming.broadcast_drive_folder(redis, current_account, drive_folder, type)
  end

  def require_feature_enabled!
    not_found unless Setting.drive_enabled
  end

  def apply_date_range(scope, column = :created_at)
    since_time = parse_time_param(params[:since_date])
    until_time = parse_time_param(params[:until_date])
    scope = scope.where(scope.model.arel_table[column].gt(since_time)) if since_time
    scope = scope.where(scope.model.arel_table[column].lt(until_time)) if until_time
    scope
  end

  def parse_time_param(value)
    return if value.blank?

    if /\A\d+\z/.match?(value.to_s)
      epoch = value.to_i
      Time.zone.at(epoch > 100_000_000_000 ? epoch / 1000.0 : epoch)
    else
      Time.zone.parse(value.to_s)
    end
  rescue ArgumentError, TypeError
    nil
  end
end
