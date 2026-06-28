# frozen_string_literal: true

# == Schema Information
#
# Table name: custom_csses
#
#  id         :bigint(8)        not null, primary key
#  css        :text             default(""), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint(8)        not null
#

class CustomCss < ApplicationRecord
  CSS_SIZE_LIMIT = 300.kilobytes

  belongs_to :user

  validates :css, length: { maximum: CSS_SIZE_LIMIT }
end
