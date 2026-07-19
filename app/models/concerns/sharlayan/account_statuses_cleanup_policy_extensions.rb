# frozen_string_literal: true

module Sharlayan::AccountStatusesCleanupPolicyExtensions
  extend ActiveSupport::Concern

  EXCEPTION_BOOLS = %w(keep_self_reaction keep_self_clip).freeze
  EXCEPTION_THRESHOLDS = %w(min_reactions).freeze

  included do
    validates :min_reactions, numericality: { greater_than_or_equal_to: 1, allow_nil: true }
  end

  private

  def apply_sharlayan_cleanup_scopes(scope)
    scope.merge!(without_self_reaction_scope) if keep_self_reaction?
    scope.merge!(without_self_clip_scope) if keep_self_clip?
    scope = scope.left_joins(:status_stat).where('COALESCE(status_stats.reactions_count, 0) < ?', min_reactions) unless min_reactions.nil?
    scope
  end

  def sharlayan_cleanup_exception_enabled?(action)
    case action
    when :unreact
      keep_self_reaction?
    when :unclip
      keep_self_clip?
    end
  end

  def without_self_reaction_scope
    Status.where('NOT EXISTS (SELECT * FROM status_reactions reaction WHERE reaction.account_id = statuses.account_id AND reaction.status_id = statuses.id)')
  end

  def without_self_clip_scope
    Status.where('NOT EXISTS (SELECT * FROM clip_statuses cs JOIN clips c ON c.id = cs.clip_id WHERE cs.status_id = statuses.id AND c.account_id = statuses.account_id)')
  end
end
