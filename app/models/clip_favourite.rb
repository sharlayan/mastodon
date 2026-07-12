# frozen_string_literal: true

# == Schema Information
#
# Table name: clip_favourites
#
#  id         :bigint(8)        not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint(8)        not null
#  clip_id    :bigint(8)        not null
#

class ClipFavourite < ApplicationRecord
  include Paginable

  belongs_to :account, inverse_of: :clip_favourites
  belongs_to :clip, inverse_of: :clip_favourites

  validates :clip_id, uniqueness: { scope: :account_id }
end
