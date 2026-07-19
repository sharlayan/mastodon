# frozen_string_literal: true

class Api::V1::Drive::UsageController < Api::V1::Drive::BaseController
  before_action -> { doorkeeper_authorize! :read, :'read:drive' }

  def show
    render json: {
      used: used_bytes,
      limit: quota_bytes,
      file_count: current_account.drive_files.count,
    }
  end

  private

  def used_bytes
    current_account.drive_files.sum(:storage_file_size).to_i
  end

  def quota_bytes
    current_account.drive_quota_bytes
  end
end
