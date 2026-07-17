# frozen_string_literal: true

module Sharlayan::RESTStatusSerialization
  extend ActiveSupport::Concern

  include Sharlayan::REST::Status::InstanceMetadata
  include Sharlayan::REST::Status::LimitedScope
  include Sharlayan::REST::Status::Mfm
  include Sharlayan::REST::Status::Reactions
end
