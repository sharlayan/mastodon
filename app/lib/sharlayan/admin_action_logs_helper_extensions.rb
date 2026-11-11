# frozen_string_literal: true

module Sharlayan::AdminActionLogsHelperExtensions
  def log_target(log)
    case log.target_type
    when 'ChatConversation'
      log.human_identifier
    when 'AvatarDecorationDomainBlock', 'DriveFile', 'VoiceRelayProvider'
      sharlayan_log_label(log)
    when 'AvatarDecoration'
      log.target.present? ? link_to(sharlayan_log_label(log), edit_admin_avatar_decoration_path(log.target_id)) : sharlayan_log_label(log)
    when 'BoardAnnouncement'
      log.target.present? ? link_to(truncate(sharlayan_log_label(log)), edit_admin_board_announcement_path(log.target_id)) : truncate(sharlayan_log_label(log))
    else
      super
    end
  end

  private

  def sharlayan_log_label(log)
    log.human_identifier.presence || "##{log.target_id}"
  end
end
