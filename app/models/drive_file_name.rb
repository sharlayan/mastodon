# frozen_string_literal: true

# == Schema Information
#
# Table name: drive_file_names
#
#  id            :bigint(8)        not null, primary key
#  name          :string(128)      default(""), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  drive_file_id :bigint(8)        not null
#

class DriveFileName < ApplicationRecord
  MAX_NAME_LENGTH = 128

  belongs_to :drive_file, inverse_of: :custom_name

  validates :name, presence: true, length: { maximum: MAX_NAME_LENGTH }
end
