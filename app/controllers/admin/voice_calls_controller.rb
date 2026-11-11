# frozen_string_literal: true

class Admin::VoiceCallsController < Admin::BaseController
  def destroy
    authorize :voice_relay_provider, :update?

    allocation = VoiceCallAllocation.find(params[:id])
    Sharlayan::VoiceCallService.new.end_call(allocation)
    log_action :end, allocation
    redirect_to admin_voice_relay_providers_path, notice: I18n.t('admin.voice_relay_providers.call_ended_msg')
  rescue Sharlayan::VoiceRelay::Error => e
    end_failed(e.code)
  rescue Mastodon::RaceConditionError
    end_failed('BUSY')
  end

  private

  def end_failed(code)
    redirect_to admin_voice_relay_providers_path, alert: I18n.t('admin.voice_relay_providers.call_end_failed_msg', code:)
  end
end
