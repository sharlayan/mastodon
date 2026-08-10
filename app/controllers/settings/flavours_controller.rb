# frozen_string_literal: true

class Settings::FlavoursController < Settings::BaseController
  include ThemeHelper

  layout 'admin'

  before_action :authenticate_user!

  skip_before_action :require_functional!

  def index
    redirect_to settings_preferences_appearance_path
  end

  def show
    redirect_to settings_preferences_appearance_path
  end

  def update
    flavour = roleplay_mode? ? 'glitch' : params.require(:flavour)
    return redirect_to(action: 'show', flavour: current_flavour) unless Themes.instance.flavours.include?(flavour)

    available_skins = Themes.instance.skins_for(flavour)
    skin = params.dig(:user, :setting_skin).presence || available_skins.first
    return redirect_to(action: 'show', flavour: current_flavour) unless available_skins.include?(skin)

    settings = { flavour: flavour, skin: skin }
    supported = Themes.instance.supported_color_schemes(flavour, skin)
    settings[:color_scheme] = supported.first if supported.one?
    current_user.settings.update(settings)
    current_user.save
    redirect_to action: 'show', flavour: flavour
  end
end
