# frozen_string_literal: true

class Api::V1::AppearanceController < Api::BaseController
  before_action -> { doorkeeper_authorize! :write, :'write:accounts' }
  before_action :require_user!

  def update
    current_user.settings.update(appearance_params)
    current_user.save!

    render json: { color_scheme: current_user.settings['web.color_scheme'], contrast: current_user.settings['web.contrast'] }
  end

  private

  def appearance_params
    settings = {
      'web.color_scheme' => params[:color_scheme],
      'web.contrast' => params[:contrast],
    }.compact

    settings.each do |key, value|
      raise Mastodon::InvalidParameterError, "Invalid value for '#{key}'" unless UserSettings.definition_for(key).in.include?(value)
    end

    settings
  end
end
