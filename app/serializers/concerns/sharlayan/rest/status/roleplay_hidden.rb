# frozen_string_literal: true

# `rp_hidden` is only serialized for the owner reading the management timeline,
# which is the single context where hidden statuses are returned at all.
module Sharlayan::REST::Status::RoleplayHidden
  extend ActiveSupport::Concern

  included do
    attribute :rp_hidden, if: :rp_admin?
  end

  def rp_admin?
    instance_options[:rp_admin].present?
  end

  def rp_hidden
    object.rp_hidden?
  end
end
