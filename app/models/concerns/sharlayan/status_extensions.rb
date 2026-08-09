# frozen_string_literal: true

module Sharlayan::StatusExtensions
  extend ActiveSupport::Concern

  include Sharlayan::Status::Collections
  include Sharlayan::Status::DomainMutes
  include Sharlayan::Status::MediaLimits
  include Sharlayan::Status::Reactions
  include Sharlayan::Status::RoleplayHidden
end
