# frozen_string_literal: true

# == Schema Information
#
# Table name: rp_hidden_statuses
#
#  id                   :bigint(8)        not null, primary key
#  media_moved          :boolean          default(FALSE), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  hidden_by_account_id :bigint(8)
#  status_id            :bigint(8)        not null
#
class RpHiddenStatus < ApplicationRecord
  belongs_to :status
  belongs_to :hidden_by_account, class_name: 'Account', optional: true
end
