# frozen_string_literal: true

class MediaAttachmentPolicy < ApplicationPolicy
  def download?
    return show_chat? if record.chat_messages.exists?

    (record.on_hold? && role.can?(:manage_reports)) || show_status?
  end

  private

  def show_chat?
    current_account.present? && record.chat_messages.joins(chat_conversation: :memberships).exists?(chat_memberships: { account_id: current_account.id })
  end

  def show_status?
    record.status && StatusPolicy.new(current_account, record.status).show?
  end
end
