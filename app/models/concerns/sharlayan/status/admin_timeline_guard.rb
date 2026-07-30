# frozen_string_literal: true

module Sharlayan::Status::AdminTimelineGuard
  extend ActiveSupport::Concern

  CONVERSATION_VISIBILITIES = %w(private direct limited).freeze

  NO_REMOTE_PARTICIPANTS_SQL = <<~SQL.squish
    statuses.visibility NOT IN (:conversation_visibilities)
    OR (
      NOT EXISTS (
        SELECT 1 FROM mentions m
        INNER JOIN accounts ma ON ma.id = m.account_id
        WHERE m.status_id = statuses.id AND ma.domain IS NOT NULL
      )
      AND NOT EXISTS (
        SELECT 1 FROM accounts ra
        WHERE ra.id = statuses.in_reply_to_account_id AND ra.domain IS NOT NULL
      )
    )
  SQL

  included do
    scope :without_remote_participants, -> { where(NO_REMOTE_PARTICIPANTS_SQL, conversation_visibilities: conversation_visibility_values) }
    scope :admin_timeline_eligible, -> { where(visibility: :public).or(where(local_only: true)).without_remote_participants }
  end

  class_methods do
    def conversation_visibility_values
      visibilities.values_at(*CONVERSATION_VISIBILITIES)
    end
  end

  def admin_timeline_eligible?
    (public_visibility? || local_only?) && !remote_participants?
  end

  def remote_participants?
    return false unless CONVERSATION_VISIBILITIES.include?(visibility.to_s)

    mentions.joins(:account).merge(Account.remote).exists? ||
      (in_reply_to_account_id.present? && Account.remote.exists?(id: in_reply_to_account_id))
  end
end
