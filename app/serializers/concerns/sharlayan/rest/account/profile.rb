# frozen_string_literal: true

module Sharlayan::REST::Account::Profile
  extend ActiveSupport::Concern

  included do
    attribute :followed_message
    attribute :is_cat
    attribute :birthday, if: :birthday_visible?
  end

  def birthday_visible?
    object.birthday_visible_to?(current_user&.account)
  end
end
