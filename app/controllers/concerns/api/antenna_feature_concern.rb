# frozen_string_literal: true

module Api::AntennaFeatureConcern
  extend ActiveSupport::Concern
  include RoleplayModeHelper

  included do
    before_action :require_antenna_enabled!
  end

  private

  def require_antenna_enabled!
    not_found if roleplay_mode? || !Setting.antenna_enabled
  end
end
