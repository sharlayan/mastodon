# frozen_string_literal: true

# == Schema Information
#
# Table name: board_announcement_reads
#
#  id                    :bigint(8)        not null, primary key
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint(8)        not null
#  board_announcement_id :bigint(8)        not null
#

class BoardAnnouncementRead < ApplicationRecord
  belongs_to :account
  belongs_to :board_announcement, inverse_of: :reads

  validates :account_id, uniqueness: { scope: :board_announcement_id }
end
