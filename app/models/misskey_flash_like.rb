# frozen_string_literal: true

# == Schema Information
#
# Table name: misskey_flash_likes
#
#  id               :bigint(8)        not null, primary key
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint(8)        not null
#  misskey_flash_id :bigint(8)        not null
#
class MisskeyFlashLike < ApplicationRecord
  belongs_to :account
  belongs_to :misskey_flash, counter_cache: :likes_count, inverse_of: :likes

  validates :account_id, uniqueness: { scope: :misskey_flash_id }
end
