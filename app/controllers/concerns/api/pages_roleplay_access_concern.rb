# frozen_string_literal: true

module Api::PagesRoleplayAccessConcern
  extend ActiveSupport::Concern
  include RoleplayModeHelper

  included do
    before_action :require_roleplay_authentication!
  end

  private

  def require_roleplay_authentication!
    require_user! if roleplay_mode?
  end
end
