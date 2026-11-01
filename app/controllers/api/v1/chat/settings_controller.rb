# frozen_string_literal: true

class Api::V1::Chat::SettingsController < Api::V1::Chat::BaseController
  POLICIES = %w(everyone followers following mutual none).freeze
  LEGACY_POLICIES = { 'mutuals' => 'mutual', 'nobody' => 'none' }.freeze

  before_action :authorize_chat_read!, only: :show
  before_action :authorize_chat_write!, only: :update
  before_action :enforce_chat_write_rate_limit!, only: :update

  def show
    render json: settings_payload
  end

  def update
    if params.key?(:policy)
      policy = LEGACY_POLICIES.fetch(params[:policy].to_s, params[:policy].to_s)
      raise Mastodon::InvalidParameterError, 'Invalid chat policy' unless POLICIES.include?(policy)

      current_user.settings[:chat_policy] = policy
    end
    current_user.settings[:chat_allow_group_invites] = boolean_param(:allow_group_invites) if params.key?(:allow_group_invites)
    current_user.settings[:chat_notifications] = boolean_param(:notifications) if params.key?(:notifications)
    current_user.save!
    render json: settings_payload
  end

  private

  def settings_payload
    {
      policy: LEGACY_POLICIES.fetch(current_user.settings[:chat_policy], current_user.settings[:chat_policy]),
      allow_group_invites: current_user.settings[:chat_allow_group_invites],
      notifications: current_user.settings[:chat_notifications],
      max_group_members: Setting.chat_max_group_members,
      max_attachments: Setting.chat_max_attachments,
      federation_enabled: Setting.chat_federation_enabled,
    }
  end

  def boolean_param(key)
    value = params[key]
    raise Mastodon::InvalidParameterError, "Invalid boolean for #{key}" unless [true, false, 'true', 'false', '1', '0'].include?(value)

    ActiveModel::Type::Boolean.new.cast(value)
  end
end
