# frozen_string_literal: true

module CollectionsFeatureConcern
  extend ActiveSupport::Concern

  include RoleplayModeHelper

  included do
    before_action :require_collections_enabled!
  end

  private

  def require_collections_enabled!
    not_found if roleplay_mode?
  end
end
