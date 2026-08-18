# frozen_string_literal: true

module Sharlayan::Account::Associations
  extend ActiveSupport::Concern

  included do
    has_many :status_reactions, inverse_of: :account, dependent: :destroy
  end
end
