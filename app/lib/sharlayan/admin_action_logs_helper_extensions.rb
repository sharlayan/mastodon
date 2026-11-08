# frozen_string_literal: true

module Sharlayan::AdminActionLogsHelperExtensions
  def log_target(log)
    return log.human_identifier if log.target_type == 'ChatConversation'

    super
  end
end
