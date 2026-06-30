# frozen_string_literal: true

class Settings::FlavoursController < Settings::BaseController
  include ThemeHelper

  layout 'admin'

  before_action :authenticate_user!

  skip_before_action :require_functional!

  def index
    redirect_to action: 'show', flavour: current_flavour
  end

  def show
    return redirect_to action: 'show', flavour: 'glitch' if roleplay_mode? && params[:flavour] != 'glitch'

    redirect_to action: 'show', flavour: current_flavour unless Themes.instance.flavours.include?(params[:flavour]) || (params[:flavour] == current_flavour)

    @listing = roleplay_mode? ? ['glitch'] : Themes.instance.flavours
    @selected = params[:flavour]
  end

  def update
    flavour = roleplay_mode? ? 'glitch' : params.require(:flavour)
    current_user.settings.update(flavour: flavour, skin: params.dig(:user, :setting_skin))
    current_user.save
    redirect_to action: 'show', flavour: flavour
  end
end
