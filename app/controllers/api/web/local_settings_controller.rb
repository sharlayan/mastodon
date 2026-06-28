# frozen_string_literal: true

class Api::Web::LocalSettingsController < Api::Web::BaseController
  before_action :require_user!

  def show
    render json: { data: LocalSettingsStore.read(current_user.id), updated_at: LocalSettingsStore.updated_at(current_user.id) }
  end

  def update
    LocalSettingsStore.write(current_user.id, settings_data)
    render json: { updated_at: LocalSettingsStore.updated_at(current_user.id) }
  rescue LocalSettingsStore::PayloadTooLarge
    render json: { error: 'Payload too large' }, status: 413
  end

  private

  def settings_data
    data = params.require(:data)
    data.respond_to?(:to_unsafe_h) ? data.to_unsafe_h : data
  end
end
