# frozen_string_literal: true

Rails.application.config.after_initialize do
  next unless ENV['OC_ROLEPLAY_OPTION'] == 'true'

  FanOutOnWriteService.prepend Sharlayan::AdminTimelineFanOut::FanOut
  RemoveStatusService.prepend Sharlayan::AdminTimelineFanOut::Remove

  begin
    next unless ActiveRecord::Base.connection.table_exists?('settings')

    # Overwrites the stored admin settings on every boot while roleplay mode is on.
    # 롤플레이 모드가 켜져 있는 동안 부팅할 때마다 저장된 관리 설정을 덮어씁니다.
    Sharlayan::RoleplayForcedSettings::SETTINGS.each do |var, value|
      setting = Setting.where(var: var.to_s).first_or_initialize(var: var.to_s)
      setting.update(value: value) unless setting.value == value
    end
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished => e
    Rails.logger.debug { "Skipping roleplay forced settings: #{e.class}" }
  end
end
