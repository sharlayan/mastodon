# frozen_string_literal: true

class PurgeStatusWorker
  include Sidekiq::Worker
  include RoleplayModeHelper

  def perform(status_id, options = {})
    return unless roleplay_mode? && Setting.soft_hide_deletion

    status = Status.unscoped.find(status_id)
    return unless status.rp_hidden?

    status.skip_counter_decrement = true

    RemoveStatusService.new.call(status, **options.symbolize_keys, immediate: true)
  rescue ActiveRecord::RecordNotFound
    true
  end
end
