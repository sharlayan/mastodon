# frozen_string_literal: true

module Sharlayan::Status::RoleplayHidden
  extend ActiveSupport::Concern

  included do
    has_one :rp_hidden_status, inverse_of: :status, dependent: :delete

    default_scope do
      scope = recent.kept
      RoleplayModeHelper.roleplay_mode? ? scope.not_rp_hidden : scope
    end

    scope :not_rp_hidden, -> { where('NOT EXISTS (SELECT 1 FROM rp_hidden_statuses WHERE rp_hidden_statuses.status_id = statuses.id)') }
  end

  class_methods do
    def with_rp_hidden
      unscoped.recent.kept
    end
  end

  def rp_hidden?
    association(:rp_hidden_status).loaded? ? rp_hidden_status.present? : RpHiddenStatus.exists?(status_id: id)
  end
end
