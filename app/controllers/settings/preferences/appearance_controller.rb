# frozen_string_literal: true

class Settings::Preferences::AppearanceController < Settings::Preferences::BaseController
  include ThemeHelper

  helper_method :available_flavours, :available_themes_for_select

  private

  def after_update_redirect_path
    settings_preferences_appearance_path
  end

  def user_params
    permitted = super
    flavour, skin = params[:theme].to_s.split('/', 2)
    return permitted unless available_theme?(flavour, skin)

    settings = permitted[:settings_attributes] ||= ActionController::Parameters.new
    settings[:flavour] = flavour
    settings[:skin] = skin
    settings[:'web.color_scheme'] = Themes.instance.resolve_color_scheme(flavour, skin, settings[:'web.color_scheme'] || current_user.setting_color_scheme)
    permitted
  end

  def available_theme?(flavour, skin)
    available_flavours.include?(flavour) && Themes.instance.skins_for(flavour).include?(skin)
  end

  def available_flavours
    roleplay_mode? ? Themes.instance.flavours & ['glitch'] : Themes.instance.flavours
  end

  def available_themes_for_select
    available_flavours.to_h do |flavour|
      label = I18n.t("flavours.#{flavour}.name", default: flavour)
      skins = Themes.instance.skins_for(flavour).map { |skin| [skin_label(flavour, skin), "#{flavour}/#{skin}"] }
      [label, skins]
    end
  end
end
