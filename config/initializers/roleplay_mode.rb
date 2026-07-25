# frozen_string_literal: true

Rails.application.config.after_initialize do
  next unless ENV['OC_ROLEPLAY_OPTION'] == 'true'

  FanOutOnWriteService.prepend Sharlayan::AdminTimelineFanOut::FanOut
  RemoveStatusService.prepend Sharlayan::AdminTimelineFanOut::Remove

  begin
    next unless ActiveRecord::Base.connection.table_exists?('settings')

    Sharlayan::RoleplayForcedSettings::SETTINGS.each do |var, value|
      setting = Setting.where(var: var.to_s).first_or_initialize(var: var.to_s)
      setting.update(value: value) unless setting.value == value
    end
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished
    # skip for not ready
  end
end
