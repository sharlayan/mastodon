# frozen_string_literal: true

module Sharlayan::LocalStatusPageAccess
  extend ActiveSupport::Concern

  private

  def local_status_page_accessible?
    return @local_status_page_accessible if defined?(@local_status_page_accessible)

    @local_status_page_accessible = Sharlayan::LocalContentAccess.accessible?(Setting.local_status_page_access, current_user)
  end

  def require_status_page_access!
    require_local_content_access!(Setting.local_status_page_access) if @status.local?
  end

  def filter_local_status_page_access(statuses)
    return statuses if local_status_page_accessible?

    statuses.reject(&:local?)
  end
end
