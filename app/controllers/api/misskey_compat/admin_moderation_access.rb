# frozen_string_literal: true

module Api::MisskeyCompat::AdminModerationAccess
  extend ActiveSupport::Concern

  MODERATOR_DENIED_ID = 'd33d5333-db36-423d-a8f9-1a2b9549da41'
  ADMINISTRATOR_DENIED_ID = 'c3d38592-54c0-429d-be96-5636b0431a61'
  INTERNAL_ERROR_ID = '5d37dbcb-891e-41ca-a3d6-e690c97775ac'

  AdminEndpoint = Struct.new(:kind, :token_area, :administrator, :secure)

  included do
    include AccountableConcern

    class_attribute :misskey_admin_endpoints, instance_writer: false, default: {}

    before_action :require_misskey_admin_access!
  end

  class_methods do
    def misskey_admin_endpoint(kind, *actions, area: nil, administrator: false, secure: false)
      endpoint = AdminEndpoint.new(kind, area, administrator, secure).freeze
      self.misskey_admin_endpoints = misskey_admin_endpoints.merge(actions.index_with { endpoint }.transform_keys(&:to_s)).freeze
    end
  end

  private

  def misskey_admin_endpoint
    misskey_admin_endpoints.fetch(action_name)
  end

  def require_misskey_admin_access!
    endpoint = misskey_admin_endpoint

    if current_user.nil?
      code = bearer_token.present? || params[:i].present? ? 'AUTHENTICATION_FAILED' : 'CREDENTIAL_REQUIRED'
      render_error('Authentication required', code, 401)
    elsif !current_user.functional?
      render_error('Account is not available', 'AUTHENTICATION_FAILED', 403)
    elsif !misskey_admin_token_allows?(endpoint)
      render_error('Insufficient token scope', 'PERMISSION_DENIED', 403)
    elsif endpoint.secure && !native_user_token?
      render_error(I18n.t('errors.403'), 'ACCESS_DENIED', 403, id: self.class::ACCESS_DENIED_ID)
    elsif !Admin::BasePolicy.new(current_account, :base).access?
      render_misskey_role_denied(endpoint)
    end
  end

  def misskey_admin_token_allows?(endpoint)
    return native_user_token? || current_misskey_grant.permissions.include?(endpoint.kind) if current_misskey_grant

    scope = endpoint.kind.start_with?('read:') ? 'admin:read' : 'admin:write'
    current_token.scopes.exists?(scope) || (endpoint.token_area.present? && current_token.scopes.exists?("#{scope}:#{endpoint.token_area}"))
  end

  def render_misskey_role_denied(endpoint)
    if endpoint.administrator
      render_error('You are not assigned to an administrator role', 'ROLE_PERMISSION_DENIED', 403, id: ADMINISTRATOR_DENIED_ID, kind: 'permission')
    else
      render_error('You are not assigned to a moderator role', 'ROLE_PERMISSION_DENIED', 403, id: MODERATOR_DENIED_ID, kind: 'permission')
    end
  end

  def render_misskey_internal_error(message)
    render_error('Internal error occurred', 'INTERNAL_ERROR', 500, id: INTERNAL_ERROR_ID, kind: 'server', info: { e: { message: message, code: 'Error' } })
  end

  def misskey_detailed_users(accounts)
    accounts = accounts.compact.uniq
    collection = MisskeyCompat::UserCollectionContext.for(accounts)
    accounts.index_by(&:id).transform_values { |account| MisskeyCompat::UserSerializer.serialize(account, detailed: true, collection:) }
  end

  def misskey_user_log_info(account)
    { userId: MisskeyCompat::MiId.encode(account.id), userUsername: account.username, userHost: account.local? ? nil : account.domain }
  end
end
