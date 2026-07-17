# frozen_string_literal: true

module Sharlayan::Status::Reactions
  extend ActiveSupport::Concern

  included do
    has_many :status_reactions, inverse_of: :status, dependent: :destroy
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
      records.group_by(&:status_id)
    end

    private

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
    grouped_ordered_status_reactions(account_id).select(
      [:status_id, :name, :custom_emoji_id, 'COUNT(*) as count'].tap do |values|
        values << value_for_reaction_me_column(account_id)
      end
    ).to_a.tap do |records|
      ActiveRecord::Associations::Preloader.new(records: records, associations: { custom_emoji: :local_counterpart }).call
    end
  end

  def reactions_count
    status_stat&.reactions_count || 0
  end

  private

  def grouped_ordered_status_reactions(account_id = nil)
    scope = status_reactions

    if account_id.present?
      excluded_account_ids = Account.find_by(id: account_id)&.excluded_from_timeline_account_ids
      scope = scope.where.not(account_id: excluded_account_ids) if excluded_account_ids.present?
    end

    scope
      .group(:status_id, :name, :custom_emoji_id)
      .order(Arel.sql('MIN(created_at)').asc)
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
