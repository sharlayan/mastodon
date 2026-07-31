# frozen_string_literal: true

module Sharlayan::Status::Reactions
  extend ActiveSupport::Concern

  REACTION_ACCEPTANCES = %w(likeOnly likeOnlyForRemote nonSensitiveOnly nonSensitiveOnlyForLocalLikeOnlyForRemote).freeze
  LIKE_REACTION = "\u2764"

  included do
    has_many :status_reactions, inverse_of: :status, dependent: :destroy
    validates :reaction_acceptance, inclusion: { in: REACTION_ACCEPTANCES }, allow_nil: true
  end

  class_methods do
    def reactions_map(status_ids, account_id)
      StatusReaction.select(:status_id).where(status_id: status_ids).where(account_id: account_id).to_h { |reaction| [reaction.status_id, true] }
    end

    def reaction_groups_map(status_ids, account_id = nil)
      scope = StatusReaction.where(status_id: status_ids)
      excluded_account_ids = Account.find_by(id: account_id)&.excluded_from_timeline_account_ids if account_id.present?
      scope = scope.where.not(account_id: excluded_account_ids) if excluded_account_ids.present?

      records = scope
        .group(:status_id, :name, :custom_emoji_id)
        .order(Arel.sql('MIN(status_reactions.created_at)').asc)
        .select(
          [:status_id, :name, :custom_emoji_id, 'COUNT(*) as count'].tap do |values|
            values << value_for_reaction_me_column(account_id)
          end
        ).to_a

      ActiveRecord::Associations::Preloader.new(records: records, associations: { custom_emoji: :local_counterpart }).call
      preload_reaction_accounts(records, status_ids, excluded_account_ids)
      records.group_by(&:status_id)
    end

    private

    def preload_reaction_accounts(records, status_ids, excluded_account_ids)
      return if records.empty?

      rows_scope = StatusReaction.where(status_id: status_ids)
      rows_scope = rows_scope.where.not(account_id: excluded_account_ids) if excluded_account_ids.present?

      grouped_account_ids = Hash.new { |hash, key| hash[key] = [] }
      rows_scope.order(:id).pluck(:status_id, :name, :custom_emoji_id, :account_id).each do |status_id, name, custom_emoji_id, account_id|
        grouped_account_ids[[status_id, name, custom_emoji_id]] << account_id
      end

      needed_ids = grouped_account_ids.values.flat_map { |ids| ids.first(StatusReaction::USERS_DISPLAY_LIMIT) }.uniq
      accounts_by_id = Account.where(id: needed_ids).index_by(&:id)

      records.each do |record|
        ids = grouped_account_ids[[record.status_id, record.name, record.custom_emoji_id]]
        record.preloaded_account_ids = ids
        record.preloaded_users = ids.first(StatusReaction::USERS_DISPLAY_LIMIT).filter_map { |id| accounts_by_id[id] }
      end
    end

    def value_for_reaction_me_column(account_id)
      return 'FALSE AS me' if account_id.nil?

      <<~SQL.squish
        EXISTS(
          SELECT 1
          FROM status_reactions inner_reactions
          WHERE inner_reactions.account_id = #{account_id.to_i}
            AND inner_reactions.status_id = status_reactions.status_id
            AND inner_reactions.name = status_reactions.name
            AND (
              inner_reactions.custom_emoji_id = status_reactions.custom_emoji_id
              OR inner_reactions.custom_emoji_id IS NULL
                AND status_reactions.custom_emoji_id IS NULL
            )
        ) AS me
      SQL
    end
  end

  def reactions(account_id = nil)
    self.class.reaction_groups_map([id], account_id)[id] || []
  end

  def reactions_count
    status_stat&.reactions_count || 0
  end

  def accepted_reaction(name, custom_emoji, reacting_account)
    remote_like_only = reacting_account.remote? && %w(likeOnlyForRemote nonSensitiveOnlyForLocalLikeOnlyForRemote).include?(reaction_acceptance)
    sensitive_disallowed = custom_emoji&.is_sensitive? && %w(nonSensitiveOnly nonSensitiveOnlyForLocalLikeOnlyForRemote).include?(reaction_acceptance)

    return [LIKE_REACTION, nil] if reaction_acceptance == 'likeOnly' || remote_like_only || sensitive_disallowed

    [name, custom_emoji]
  end
end
