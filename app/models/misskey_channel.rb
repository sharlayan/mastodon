# frozen_string_literal: true

# == Schema Information
#
# Table name: misskey_channels
#
#  id                       :bigint(8)        not null, primary key
#  allow_renote_to_external :boolean          default(TRUE), not null
#  archived                 :boolean          default(FALSE), not null
#  color                    :string           default("#86b300"), not null
#  description              :text
#  last_noted_at            :datetime
#  name                     :string           not null
#  notes_count              :integer          default(0), not null
#  pinned_status_ids        :bigint(8)        default([]), not null, is an Array
#  sensitive                :boolean          default(FALSE), not null
#  users_count              :integer          default(0), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint(8)
#  banner_drive_file_id     :bigint(8)
#
class MisskeyChannel < ApplicationRecord
  NAME_LENGTH_LIMIT = 128
  DESCRIPTION_LENGTH_LIMIT = 2048
  COLOR_LENGTH_LIMIT = 16
  DEFAULT_COLOR = '#86b300'

  belongs_to :account, optional: true
  belongs_to :banner_drive_file, class_name: 'DriveFile', optional: true

  has_many :followings, class_name: 'MisskeyChannelFollowing', inverse_of: :misskey_channel, dependent: :delete_all
  has_many :favorites, class_name: 'MisskeyChannelFavorite', inverse_of: :misskey_channel, dependent: :delete_all
  has_many :mutings, class_name: 'MisskeyChannelMuting', inverse_of: :misskey_channel, dependent: :delete_all
  has_many :channel_notes, class_name: 'MisskeyChannelNote', inverse_of: :misskey_channel, dependent: :delete_all

  scope :unarchived, -> { where(archived: false) }

  validates :name, presence: true, length: { maximum: NAME_LENGTH_LIMIT }
  validates :description, length: { maximum: DESCRIPTION_LENGTH_LIMIT }
  validates :color, presence: true, length: { maximum: COLOR_LENGTH_LIMIT }

  def editable_by?(account)
    return false if account.nil?

    account_id == account.id || account.user&.can?(:manage_reports) || false
  end
end
