# frozen_string_literal: true

class Api::V1::Drive::SettingsController < Api::V1::Drive::BaseController
  before_action -> { doorkeeper_authorize! :read }, only: :show
  before_action -> { doorkeeper_authorize! :write, :'write:accounts' }, only: :update

  def show
    render_settings
  end

  def update
    current_user.settings[:drive_keep_original_filename] = boolean_param(:keep_original_filename)
    current_user.settings[:drive_upload_original_image] = boolean_param(:upload_original_image) if params.key?(:upload_original_image)
    current_user.settings[:drive_default_folder_id] = default_folder_id
    current_user.save!

    render_settings
  end

  private

  def render_settings
    render json: {
      keep_original_filename: current_user.settings[:drive_keep_original_filename],
      default_folder_id: valid_default_folder_id,
      upload_original_image: current_user.settings[:drive_upload_original_image],
    }
  end

  def boolean_param(key)
    ActiveModel::Type::Boolean.new.cast(params.require(key))
  end

  def default_folder_id
    folder_id = params[:default_folder_id].presence
    return if folder_id.nil?

    current_account.drive_folders.find(folder_id).id.to_s
  end

  def valid_default_folder_id
    folder_id = current_user.settings[:drive_default_folder_id].presence
    folder_id if folder_id && current_account.drive_folders.exists?(id: folder_id)
  end
end
