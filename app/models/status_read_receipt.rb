# frozen_string_literal: true

# == Schema Information
#
# Table name: status_read_receipts
#
#  id         :bigint(8)        not null, primary key
#  read_at    :datetime         not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint(8)        not null
#  status_id  :bigint(8)        not null
#
class StatusReadReceipt < ApplicationRecord
  belongs_to :status
  belongs_to :account

  validates :account_id, uniqueness: { scope: :status_id }
end
