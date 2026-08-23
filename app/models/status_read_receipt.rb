# frozen_string_literal: true

class StatusReadReceipt < ApplicationRecord
  belongs_to :status
  belongs_to :account

  validates :account_id, uniqueness: { scope: :status_id }
end
