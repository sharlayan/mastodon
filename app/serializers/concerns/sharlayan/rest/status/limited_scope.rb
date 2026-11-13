# frozen_string_literal: true

module Sharlayan::REST::Status::LimitedScope
  extend ActiveSupport::Concern

  included do
    attribute :limited_scope, if: :limited_scope?
    attribute :circle_id, if: :source_circle?
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
    @circle_id.to_s
  end

  def source_circle?
    return false unless instance_options[:source_requested] && object.limited_visibility?

    @circle_id = CircleStatus.where(status_id: object.id).joins(:circle).where(circles: { account_id: object.account_id }).pick(:circle_id)
    @circle_id.present?
  end
end
