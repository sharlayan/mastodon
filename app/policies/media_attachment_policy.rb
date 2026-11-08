# frozen_string_literal: true

class MediaAttachmentPolicy < ApplicationPolicy
  def download?
    (record.on_hold? && role.can?(:manage_reports)) || show_status? || show_chat?
  end

  private

  def show_chat?
    Setting.chat_enabled && current_user&.functional? &&
      record.chat_messages
        .where(deleted_at: nil)
        .merge(ChatMessage.visible_to(current_account))
        .joins(chat_conversation: :memberships)
        .exists?(chat_memberships: { account_id: current_account.id })
  end

  def show_status?
    record.status && StatusPolicy.new(current_account, record.status).show?
  end
end
