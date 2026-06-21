# frozen_string_literal: true

class Settings::Preferences::CustomCssController < Settings::Preferences::BaseController
  private

  def after_update_redirect_path
    settings_preferences_custom_css_path
  end

  def user_params
    if Setting.allow_user_custom_css
      params.expect(user: [:custom_css_text, settings_attributes: [:'web.use_custom_css', :'web.use_server_css']])
    else
      params.expect(user: [settings_attributes: [:'web.use_server_css']])
    end
  end
end
