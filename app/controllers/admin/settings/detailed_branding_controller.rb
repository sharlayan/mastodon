# frozen_string_literal: true

class Admin::Settings::DetailedBrandingController < Admin::SettingsController
  include RoleplayModeHelper

  before_action :set_section

  private

  def after_update_redirect_path
    case @section
    when 'appearance' then admin_settings_custom_appearance_path
    when 'misskey_flavour' then admin_settings_custom_misskey_flavour_path
    when 'extensions' then admin_settings_custom_extensions_path
    when 'timeline_control' then admin_settings_custom_timeline_control_path
    else admin_settings_detailed_branding_path
    end
  end

  def set_section
    @section = params[:section].presence_in(%w(appearance misskey_flavour extensions timeline_control)) || 'detailed_branding'
    not_found if @section == 'timeline_control' && !roleplay_mode?
    @form_url = after_update_redirect_path
  end
end
