# frozen_string_literal: true

module Sharlayan::RESTAccountSerialization
  extend ActiveSupport::Concern

  include Sharlayan::REST::Account::Decorations
  include Sharlayan::REST::Account::InstanceMetadata
  include Sharlayan::REST::Account::Mfm
  include Sharlayan::REST::Account::OnlineStatus
  include Sharlayan::REST::Account::Pages
  include Sharlayan::REST::Account::Profile
  include Sharlayan::REST::Account::RequestScopedCache
end
