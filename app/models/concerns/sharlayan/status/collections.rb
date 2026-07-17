# frozen_string_literal: true

module Sharlayan::Status::Collections
  extend ActiveSupport::Concern

  included do
    has_many :clip_statuses, inverse_of: :status, dependent: :destroy
  end
end
