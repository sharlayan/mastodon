# frozen_string_literal: true

# == Schema Information
#
# Table name: misskey_channel_notes
#
#  id                 :bigint(8)        not null, primary key
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint(8)        not null
#  misskey_channel_id :bigint(8)        not null
#  status_id          :bigint(8)        not null
#
class MisskeyChannelNote < ApplicationRecord
  belongs_to :status
  belongs_to :misskey_channel, inverse_of: :channel_notes
  belongs_to :account

  before_validation :set_account
  after_create :record_channel_activity

  validates :status_id, uniqueness: true

  def self.channel_ids_by_status_id(status_ids)
    ids = Array(status_ids).compact.uniq
    return {} if ids.empty?

    where(status_id: ids).pluck(:status_id, :misskey_channel_id).to_h
  end

  def self.channels_by_status_id(status_ids)
    channel_ids = channel_ids_by_status_id(status_ids)
    channels = MisskeyChannel.where(id: channel_ids.values.uniq).index_by(&:id)
    channel_ids.transform_values { |channel_id| channels[channel_id] }.compact
  end

  def self.linked_status_condition(column = Status.arel_table[:id])
    where(arel_table[:status_id].eq(column)).arel.exists
  end

  def self.muted_status_condition(account, column)
    where(arel_table[:status_id].eq(column))
      .where(misskey_channel_id: MisskeyChannelMuting.active.where(account: account).select(:misskey_channel_id))
      .arel.exists
  end

  def self.filter_user_notes(scope, owner:, viewer:, with_channel_notes:)
    muted_channel_ids = MisskeyChannelMuting.channel_ids_for(viewer)
    muted = where(misskey_channel_id: muted_channel_ids)

    if with_channel_notes
      scope = scope.where.not(where(misskey_channel_id: MisskeyChannel.where(sensitive: true).select(:id)).linked_status_condition) unless viewer&.id == owner.id
      scope = scope.where.not(muted.linked_status_condition) if muted_channel_ids.any?
    else
      scope = scope.where.not(linked_status_condition)
    end

    muted_channel_ids.any? ? scope.where.not(muted.linked_status_condition(Status.arel_table[:reblog_of_id])) : scope
  end

  private

  def set_account
    self.account_id ||= status&.account_id
  end

  def record_channel_activity
    first_note = !self.class.where(misskey_channel_id: misskey_channel_id, account_id: account_id).where.not(id: id).exists?
    updates = ['notes_count = notes_count + 1', 'last_noted_at = :now', 'updated_at = :now']
    updates << 'users_count = users_count + 1' if first_note
    MisskeyChannel.where(id: misskey_channel_id).update_all([updates.join(', '), { now: Time.now.utc }])
  end
end
