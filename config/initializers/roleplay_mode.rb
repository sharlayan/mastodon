# frozen_string_literal: true

Rails.application.config.after_initialize do
  if Sharlayan::AdminTimeline.enabled?
    FanOutOnWriteService.prepend Sharlayan::AdminTimelineFanOut::FanOut
    RemoveStatusService.prepend Sharlayan::AdminTimelineFanOut::Remove
  end

  next unless RoleplayModeHelper.roleplay_mode?

  begin
    next unless ActiveRecord::Base.connection.table_exists?('settings')

    Sharlayan::RoleplayForcedSettings.apply_defaults!

    Sharlayan::RoleplayForcedSettings.apply_forced!
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished => e
    Rails.logger.debug { "Skipping roleplay forced settings: #{e.class}" }
  end

  begin
    next unless ActiveRecord::Base.connection.table_exists?('statuses')

    Rails.configuration.x.roleplay_non_local_only_statuses = Status.local.not_local_only.exists?
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished => e
    Rails.logger.debug { "Skipping roleplay non-local-only status check: #{e.class}" }
  end
end
