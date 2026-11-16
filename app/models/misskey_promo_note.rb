# frozen_string_literal: true

# == Schema Information
#
# Table name: misskey_promo_notes
#
#  id         :bigint(8)        not null, primary key
#  expires_at :datetime         not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint(8)        not null
#  status_id  :bigint(8)        not null
#
class MisskeyPromoNote < ApplicationRecord
  belongs_to :status
  belongs_to :account

  validates :status_id, uniqueness: true
  validates :expires_at, presence: true
end
