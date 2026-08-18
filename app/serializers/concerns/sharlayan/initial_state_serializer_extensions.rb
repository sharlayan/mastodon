# frozen_string_literal: true

module Sharlayan::InitialStateSerializerExtensions
  extend ActiveSupport::Concern

  prepended do
    attribute :max_reactions
  end

  def max_reactions
    StatusReactionValidator::LIMIT
  end

  def meta
    store = super
    store.merge!(signed_in_meta) if object.current_account
    store
  end

  private

  def signed_in_meta
    {
      visible_reactions: object_account_user.setting_visible_reactions,
      reaction_local_emoji_only: Setting.reaction_local_emoji_only,
      reactions_enabled: Setting.reactions_enabled,
    }
  end
end
