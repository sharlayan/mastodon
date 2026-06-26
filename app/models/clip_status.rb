# frozen_string_literal: true

# == Schema Information
#
# Table name: clip_statuses
#
#  id         :bigint(8)        not null, primary key
#  clip_id    :bigint(8)        not null
#  status_id  :bigint(8)        not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#

class ClipStatus < ApplicationRecord
  include Paginable

  belongs_to :clip
  belongs_to :status

  validates :status_id, uniqueness: { scope: :clip_id }
end
