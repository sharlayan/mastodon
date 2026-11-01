# frozen_string_literal: true

class REST::ChatConversationSerializer < ActiveModel::Serializer
  attributes :id, :type, :title, :description, :unread, :muted, :archived, :current_role, :created_at, :updated_at

  has_many :accounts, serializer: REST::AccountSerializer
  has_one :visible_last_message, key: :last_message, serializer: REST::ChatMessageSerializer

  def id
    object.id.to_s
  end

  def type
    object.conversation_type
  end

  def unread
    membership = object.memberships.find { |item| item.account_id == instance_options[:current_account]&.id }
    visible_last_message.present? && visible_last_message.id != membership&.last_read_message_id
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
    @visible_last_message ||= object.messages.visible_to(instance_options[:current_account]).first
  end

  def current_membership
    @current_membership ||= object.memberships.find { |item| item.account_id == instance_options[:current_account]&.id }
  end
end
