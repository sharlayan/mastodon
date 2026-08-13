# frozen_string_literal: true

class Api::V1::AppearanceController < Api::BaseController
  USER_THEME_MAX_BYTES = 32.kilobytes
  USER_THEME_MAX_ENCODED_BYTES = 44.kilobytes

  before_action -> { doorkeeper_authorize! :write, :'write:accounts' }
  before_action :require_user!

  def update
    current_user.settings.update(appearance_params)
    current_user.save!

    render json: {
      color_scheme: current_user.settings['web.color_scheme'],
      contrast: current_user.settings['web.contrast'],
      expand_content_warnings: current_user.settings['web.expand_content_warnings'],
      user_theme: current_user.settings['web.user_theme'],
    }
  end

  private

  def appearance_params
    settings = {
      'web.color_scheme' => params[:color_scheme],
      'web.contrast' => params[:contrast],
    }.compact

    if params.key?(:expand_content_warnings)
      value = params[:expand_content_warnings]
      raise Mastodon::InvalidParameterError, "Invalid value for 'web.expand_content_warnings'" unless [true, false, 'true', 'false'].include?(value)

      settings['web.expand_content_warnings'] = ActiveModel::Type::Boolean.new.cast(value)
    end

    if params.key?(:user_theme)
      value = params[:user_theme].to_s
      raise Mastodon::InvalidParameterError, "Invalid value for 'web.user_theme'" if value.bytesize > USER_THEME_MAX_ENCODED_BYTES

      decoded_size = begin
        Base64.strict_decode64(value).bytesize
      rescue ArgumentError
        raise Mastodon::InvalidParameterError, "Invalid value for 'web.user_theme'"
      end
      raise Mastodon::InvalidParameterError, "Invalid value for 'web.user_theme'" if decoded_size > USER_THEME_MAX_BYTES

      settings['web.user_theme'] = value
    end

    settings.each do |key, value|
      allowed_values = UserSettings.definition_for(key).in
      raise Mastodon::InvalidParameterError, "Invalid value for '#{key}'" if allowed_values.present? && allowed_values.exclude?(value)
    end

    settings
  end
end
