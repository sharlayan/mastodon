# frozen_string_literal: true

module Sharlayan::REST::Status::LimitedScope
  extend ActiveSupport::Concern

  included do
    attribute :limited_scope, if: :limited_scope?
  end

  def limited_scope?
    object.limited_visibility? && object.limited_scope.present?
  end
end
