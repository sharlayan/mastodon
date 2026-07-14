# frozen_string_literal: true

# == Schema Information
#
# Table name: drive_folders
#
#  id         :bigint(8)        not null, primary key
#  name       :string           default(""), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint(8)        not null
#  parent_id  :bigint(8)
#

class DriveFolder < ApplicationRecord
  MAX_NAME_LENGTH = 200

  belongs_to :account
  belongs_to :parent, class_name: 'DriveFolder', optional: true
  has_many :children, class_name: 'DriveFolder', foreign_key: :parent_id, inverse_of: :parent, dependent: :nullify
  has_many :drive_files, foreign_key: :folder_id, inverse_of: :folder, dependent: :nullify

  validates :name, presence: true, length: { maximum: MAX_NAME_LENGTH }
  validate :validate_parent_ownership
  validate :validate_no_cycle

  scope :ordered, -> { order(name: :asc, id: :asc) }
  scope :roots, -> { where(parent_id: nil) }

  def files_count
    drive_files.count
  end

  def folders_count
    children.count
  end

  private

  def validate_parent_ownership
    return if parent_id.blank?

    errors.add(:parent_id, :invalid) if parent.nil? || parent.account_id != account_id
  end

  def validate_no_cycle
    return if parent_id.blank?

    node = parent
    while node
      if node.id == id
        errors.add(:parent_id, :invalid)
        break
      end
      node = node.parent
    end
  end
end
