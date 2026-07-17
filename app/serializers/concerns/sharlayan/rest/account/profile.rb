# frozen_string_literal: true

module Sharlayan::REST::Account::Profile
  extend ActiveSupport::Concern

  included do
    attribute :followed_message
  end
end
