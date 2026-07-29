# frozen_string_literal: true

module Sharlayan::Account::Associations
  extend ActiveSupport::Concern

  included do
    with_options dependent: :destroy do
      with_options inverse_of: :account do
        has_many :favorite_emojis
        has_many :status_reactions
        has_many :circles, dependent: :destroy
        has_many :circle_accounts, dependent: :destroy
        has_many :clips, dependent: :destroy
        has_many :clip_favourites, dependent: :destroy
        has_many :favourite_clips, through: :clip_favourites, source: :clip
        has_many :drive_files, dependent: :destroy
        has_many :drive_folders, dependent: :destroy
        has_many :pages, dependent: :destroy
        has_many :page_series, dependent: :destroy
        has_many :page_likes, dependent: :destroy
        has_many :antennas, inverse_of: :account, dependent: :destroy
        has_many :misskey_registry_items, dependent: :destroy
        has_many :avatar_decoration_mutes
        has_many :reaction_mutes, dependent: :destroy
        has_many :custom_emoji_mutes, dependent: :destroy
      end

      with_options foreign_key: :target_account_id, inverse_of: :target_account do
        has_many :avatar_decoration_mutes_targeting_account, class_name: 'AvatarDecorationMute'
        has_many :reaction_mutes_targeting_account, class_name: 'ReactionMute', dependent: :destroy
      end
    end

    has_many :account_switch_authorizations, inverse_of: :account, dependent: :destroy
    has_many :switchable_accounts, through: :account_switch_authorizations, source: :target_account
  end
end
