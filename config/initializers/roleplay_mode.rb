# frozen_string_literal: true

Rails.application.config.after_initialize do
  next unless RoleplayModeHelper.roleplay_mode?

  begin
    next unless ActiveRecord::Base.connection.table_exists?('settings')

    # DESTRUCTIVE: Rewrites forced settings while roleplay mode is enabled.
    # 파괴적: 롤플레이 모드가 켜진 동안 강제 설정을 덮어씁니다.
    Sharlayan::RoleplayForcedSettings::SETTINGS.each do |var, value|
      setting = Setting.where(var: var.to_s).first_or_initialize(var: var.to_s)
      setting.update(value: value) unless setting.value == value
    end
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished => e
    Rails.logger.debug { "Skipping roleplay forced settings: #{e.class}" }
  end
end
