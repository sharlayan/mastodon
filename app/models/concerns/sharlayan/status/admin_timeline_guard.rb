# frozen_string_literal: true

module Sharlayan::Status::AdminTimelineGuard
  extend ActiveSupport::Concern

  included do
    scope :admin_timeline_eligible, -> { where(visibility: :public).or(where(local_only: true)) }
  end

  def admin_timeline_eligible?
    public_visibility? || local_only?
  end
end
