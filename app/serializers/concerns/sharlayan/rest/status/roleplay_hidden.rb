# frozen_string_literal: true

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
