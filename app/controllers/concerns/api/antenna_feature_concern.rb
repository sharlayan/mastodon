# frozen_string_literal: true

module Api::AntennaFeatureConcern
  extend ActiveSupport::Concern

  included do
    before_action :require_antenna_enabled!
  end

  private

  def require_antenna_enabled!
    not_found unless Setting.antenna_enabled
  end
end
