# frozen_string_literal: true

module Sharlayan::AccountExtensions
  extend ActiveSupport::Concern

  include Sharlayan::Account::Associations
  include Sharlayan::Account::AvatarDecorations
  include Sharlayan::Account::DomainMutes
  include Sharlayan::Account::Drive
  include Sharlayan::Account::Interactions
  include Sharlayan::Account::Profile
end
