# frozen_string_literal: true

# == Schema Information
#
# Table name: misskey_gallery_likes
#
#  id                      :bigint(8)        not null, primary key
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  account_id              :bigint(8)        not null
#  misskey_gallery_post_id :bigint(8)        not null
#
class MisskeyGalleryLike < ApplicationRecord
  belongs_to :account
  belongs_to :misskey_gallery_post, counter_cache: :likes_count, inverse_of: :likes

  validates :account_id, uniqueness: { scope: :misskey_gallery_post_id }
end
