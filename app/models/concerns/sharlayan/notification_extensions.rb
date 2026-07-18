# frozen_string_literal: true

module Sharlayan::NotificationExtensions
  extend ActiveSupport::Concern

  LEGACY_TYPE_CLASS_MAP = {
    'StatusReaction' => :reaction,
  }.freeze

  PROPERTIES = {
    follow_accepted: {
      filterable: false,
    }.freeze,
    reaction: {
      filterable: true,
    }.freeze,
  }.freeze

  TARGET_STATUS_INCLUDES_BY_TYPE = {
    reaction: [status_reaction: [:status, :custom_emoji]],
  }.freeze

  prepended do
    belongs_to :status_reaction, foreign_key: 'activity_id', inverse_of: :notification, optional: true
  end

  def reaction
    status_reaction
  end

  def target_status
    return status_reaction&.status if type == :reaction

    super
  end

  private

  def set_from_account
    if new_record? && activity_type == 'StatusReaction'
      self.from_account_id = activity&.account_id
    elsif new_record? && activity_type == 'Follow' && type == :follow_accepted
      self.from_account_id = activity&.target_account_id
    else
      super
    end
  end
end
