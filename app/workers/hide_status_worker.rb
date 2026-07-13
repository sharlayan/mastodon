# frozen_string_literal: true

class HideStatusWorker
  include Sidekiq::Worker
  include RoleplayModeHelper

  def perform(status_id, options = {})
    return unless roleplay_mode? && Setting.soft_hide_deletion

    HideStatusService.new.call(Status.with_rp_hidden.find(status_id), **options.symbolize_keys)
  rescue ActiveRecord::RecordNotFound
    true
  end
end
