# frozen_string_literal: true

class ChatConversation < ApplicationRecord
  enum :conversation_type, { direct: 0, group: 1 }, prefix: :chat

  belongs_to :owner_account, class_name: 'Account', optional: true
  belongs_to :last_message, class_name: 'ChatMessage', optional: true

  has_many :memberships, class_name: 'ChatMembership', dependent: :destroy, inverse_of: :chat_conversation
  has_many :accounts, through: :memberships
  has_many :messages, -> { order(id: :desc) }, class_name: 'ChatMessage', dependent: :delete_all, inverse_of: :chat_conversation
  has_many :invitations, class_name: 'ChatInvitation', dependent: :destroy, inverse_of: :chat_conversation
  has_many :roster_states, class_name: 'ChatRosterState', dependent: :delete_all, inverse_of: :chat_conversation

  before_destroy :schedule_message_media_removal, prepend: true
  before_destroy :remember_voice_call_allocations
  after_destroy_commit :end_voice_calls
  after_update_commit :end_voice_calls_when_archived, if: -> { saved_change_to_archived_at? && archived? }

  validates :direct_key, presence: true, uniqueness: true, if: :chat_direct?
  validates :direct_key, absence: true, if: :chat_group?
  validates :title, length: { maximum: 256 }, allow_blank: true
  validates :title, presence: true, if: :chat_group?
  validates :description, length: { maximum: 2048 }, allow_blank: true

  scope :for_account, ->(account) { joins(:memberships).where(chat_memberships: { account_id: account.id }) }
  scope :local_only, -> { where(owner_account_id: nil).or(where(owner_account_id: Account.local.select(:id))) }
  scope :between_local_accounts, -> { local_only.where.not(id: ChatMembership.where(account_id: Account.remote.select(:id)).select(:chat_conversation_id)) }

  def archived?
    archived_at.present?
  end

  def remote?
    owner_account&.remote? == true || accounts.any?(&:remote?) || pending_remote_invitee?
  end

  def local?
    owner_account.nil? || owner_account.local?
  end

  def to_log_human_identifier
    title.present? ? "#{title} (##{id})" : "##{id}"
  end

  def destroy_if_unused!
    return if accounts.local.exists? || invitations.pending.exists?

    destroy!
  end

  private

  def remember_voice_call_allocations
    @voice_call_allocation_ids = VoiceCallAllocation.unfinished.where(chat_conversation_id: id).pluck(:id)
  end

  def end_voice_calls
    allocation_ids = @voice_call_allocation_ids || VoiceCallAllocation.unfinished.where(chat_conversation_id: id).pluck(:id)
    allocation_ids.each { |allocation_id| VoiceCallEndWorker.perform_async(allocation_id) }
  end

  def end_voice_calls_when_archived
    end_voice_calls
  end

  def schedule_message_media_removal
    media_ids = ChatMessageMediaAttachment.where(chat_message_id: ChatMessage.where(chat_conversation_id: id).select(:id)).pluck(:media_attachment_id)
    return if media_ids.empty?

    ActiveRecord.after_all_transactions_commit { ChatMediaRemovalWorker.remove(media_ids) }
  end

  def pending_remote_invitee?
    return invitations.any? { |invitation| invitation.pending? && invitation.invitee_account.remote? } if invitations.loaded?

    invitations.pending.joins(:invitee_account).merge(Account.remote).exists?
  end
end
