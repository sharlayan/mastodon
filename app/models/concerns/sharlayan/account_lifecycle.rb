# frozen_string_literal: true

module Sharlayan::AccountLifecycle
  extend ActiveSupport::Concern

  include Sharlayan::Account::InstanceMetadata
  include Sharlayan::Account::Mfm
end
