# frozen_string_literal: true

module Sharlayan::Status::RoleplayHidden
  extend ActiveSupport::Concern

  module CounterCaches
    private

    def decrement_counter_caches
      return if skip_counter_decrement

      super
    end
  end

  included do
    prepend CounterCaches

    attr_accessor :skip_counter_decrement

    has_one :rp_hidden_status, inverse_of: :status, dependent: :delete

    default_scope { RoleplayModeHelper.roleplay_mode? ? not_rp_hidden : all }

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
