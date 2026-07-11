# frozen_string_literal: true

# == Schema Information
#
# Table name: page_likes
#
#  id         :bigint(8)        not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint(8)        not null
#  page_id    :bigint(8)        not null
#

class PageLike < ApplicationRecord
  belongs_to :account
  belongs_to :page, counter_cache: :likes_count

  validates :account_id, uniqueness: { scope: :page_id }
end
