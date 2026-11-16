# frozen_string_literal: true

# == Schema Information
#
# Table name: misskey_notifications
#
#  id                :bigint(8)        not null, primary key
#  data              :jsonb            not null
#  notification_type :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint(8)        not null
#  from_account_id   :bigint(8)
#
class MisskeyNotification < ApplicationRecord
  TYPES = %w(scheduledNotePosted scheduledNotePostFailed roleAssigned chatRoomInvitationReceived achievementEarned exportCompleted login createToken app test).freeze
  PER_ACCOUNT_LIMIT = 500

  belongs_to :account
  belongs_to :from_account, class_name: 'Account', optional: true

  validates :notification_type, inclusion: { in: TYPES }

  before_create :assign_shared_notification_id

  scope :of_types, ->(types) { where(notification_type: types) }

  def self.latest_id_for(account)
    where(account: account).maximum(:id)
  end

  def self.trim!(account)
    stale = where(account: account).order(id: :desc).offset(PER_ACCOUNT_LIMIT).pick(:id)
    where(account: account).where(id: ..stale).delete_all if stale
  end

  private

  def assign_shared_notification_id
    self.id = self.class.connection.select_value("SELECT nextval('notifications_id_seq')")
  end
end
