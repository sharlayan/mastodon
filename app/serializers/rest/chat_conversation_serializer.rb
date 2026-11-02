# frozen_string_literal: true

class REST::ChatConversationSerializer < ActiveModel::Serializer
  attributes :id, :type, :title, :description, :unread, :muted, :archived, :current_role, :created_at, :updated_at, :remote, :owner_account_id

  has_many :accounts, serializer: REST::AccountSerializer
  has_one :visible_last_message, key: :last_message, serializer: REST::ChatMessageSerializer

  def id
    object.id.to_s
  end

  def type
    object.conversation_type
  end

  def remote
    object.remote?
  end

  def owner_account_id
    object.owner_account_id&.to_s
  end

  def unread
    return false if visible_last_message.nil?

    last_read_id = current_membership&.last_read_message_id
    last_read_id.nil? || visible_last_message.id > last_read_id
  end

  def current_role
    current_membership&.role
  end

  def muted
    current_membership&.muted? || false
  end

  def archived
    object.archived?
  end

  def visible_last_message
    return if current_membership.nil?

    @visible_last_message ||= begin
      candidate = object.last_message
      candidate = nil if candidate && candidate.account_id == instance_options[:current_account]&.id && candidate.hidden?
      candidate || object.messages.visible_to(instance_options[:current_account]).first
    end
  end

  def current_membership
    @current_membership ||= object.memberships.find { |item| item.account_id == instance_options[:current_account]&.id }
  end
end
