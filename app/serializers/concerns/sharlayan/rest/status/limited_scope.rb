# frozen_string_literal: true

module Sharlayan::REST::Status::LimitedScope
  extend ActiveSupport::Concern

  included do
    attribute :limited_scope, if: :limited_scope?
    attribute :circle_id, if: :source_circle?
    attribute :circle, if: :owner_circle?
    attribute :limited_reply_account_ids, if: :source_reply?
  end

  def limited_scope?
    object.limited_visibility?
  end

  def limited_scope
    object.limited_scope || 'none'
  end

  def limited_reply_account_ids
    object.mentions.pluck(:account_id).map(&:to_s)
  end

  def source_reply?
    instance_options[:source_requested] && object.limited_visibility? && object.limited_reply?
  end

  def circle_id
    owned_circle[:id]
  end

  def source_circle?
    instance_options[:source_requested] && object.limited_visibility? && owned_circle.present?
  end

  def circle
    owned_circle
  end

  def owner_circle?
    !instance_options[:source_requested] &&
      current_user? &&
      current_user.account_id == object.account_id &&
      object.limited_visibility? &&
      (object.limited_circle? || object.limited_personal?) &&
      owned_circle.present?
  end

  private

  def owned_circle
    return @owned_circle if defined?(@owned_circle)

    id, title = CircleStatus.where(status_id: object.id).joins(:circle).where(circles: { account_id: object.account_id }).pick(:circle_id, 'circles.title')
    @owned_circle = id.present? ? { id: id.to_s, title: title } : nil
  end
end
