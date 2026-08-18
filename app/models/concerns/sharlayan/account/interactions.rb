# frozen_string_literal: true

module Sharlayan::Account::Interactions
  extend ActiveSupport::Concern

  def reacted?(status, name = nil, custom_emoji = nil)
    if name.nil?
      status.proper.status_reactions.exists?(account: self)
    else
      status.proper.status_reactions.exists?(account: self, name: name, custom_emoji: custom_emoji)
    end
  end
end
