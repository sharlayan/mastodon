# frozen_string_literal: true

class Api::V1::Chat::SettingsController < Api::V1::Chat::BaseController
  before_action :authorize_chat_read!, only: :show
  before_action :authorize_chat_write!, only: :update
  before_action :enforce_chat_write_rate_limit!, only: :update

  def show
    render json: settings_payload
  end

  def update
    previous_policy = current_user.settings[:chat_policy]

    if params.key?(:policy)
      policy = Sharlayan::ChatFederation::ChatScope.normalize(params[:policy].to_s, default: nil)
      raise Mastodon::InvalidParameterError, 'Invalid chat policy' if policy.nil?

      current_user.settings[:chat_policy] = policy
    end
    current_user.settings[:chat_allow_group_invites] = boolean_param(:allow_group_invites) if params.key?(:allow_group_invites)
    current_user.settings[:chat_notifications] = boolean_param(:notifications) if params.key?(:notifications)
    current_user.save!
    ActivityPub::UpdateDistributionWorker.perform_in(ActivityPub::UpdateDistributionWorker::DEBOUNCE_DELAY, current_account.id) if current_user.settings[:chat_policy] != previous_policy
    render json: settings_payload
  end

  private

  def settings_payload
    {
      policy: Sharlayan::ChatFederation::ChatScope.normalize(current_user.settings[:chat_policy]),
      allow_group_invites: current_user.settings[:chat_allow_group_invites],
      notifications: current_user.settings[:chat_notifications],
      max_group_members: Setting.chat_max_group_members,
      max_attachments: Setting.chat_max_attachments,
      federation_enabled: Sharlayan::ChatFederation.enabled?,
      delete_window_hours: Setting.chat_delete_window_hours,
      soft_delete: RoleplayModeHelper.roleplay_mode? || Setting.chat_soft_delete_enabled,
      room_deletion: Sharlayan::ChatService.room_deletion_enabled?,
      voice_calls: voice_calls_permitted?,
      voice_call_screen_share: voice_calls_permitted? && Sharlayan::VoiceCallService.permitted?(current_account, :share_screens),
    }
  end

  def voice_calls_permitted?
    return @voice_calls_permitted if defined?(@voice_calls_permitted)

    @voice_calls_permitted = Sharlayan::VoiceCallService.permitted?(current_account) &&
                             ((Sharlayan::VoiceCallService.enabled? && VoiceRelayProvider.usable.exists?) || Sharlayan::VoiceCallFederation.remote_join_enabled?)
  end

  def boolean_param(key)
    value = params[key]
    raise Mastodon::InvalidParameterError, "Invalid boolean for #{key}" unless [true, false, 'true', 'false', '1', '0'].include?(value)

    ActiveModel::Type::Boolean.new.cast(value)
  end
end
