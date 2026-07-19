# frozen_string_literal: true

module Sharlayan::Account::Profile
  extend ActiveSupport::Concern

  included do
    validates :followed_message, length: { maximum: 256 }, if: -> { local? && will_save_change_to_followed_message? }
  end

  def featureable?
    local? && discoverable?
  end

  def sharlayan_emojifiable_text
    followed_message
  end
end
