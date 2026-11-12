# frozen_string_literal: true

class Api::MisskeyCompat::Admin::ServerBaseController < Api::MisskeyCompat::BaseController
  include AccountableConcern

  CREDENTIAL_REQUIRED_ID = '1384574d-a912-4b81-8601-c7b1c4085df1'
  SUSPENDED_ID = 'a8c724b3-6e9c-4b46-b1a8-bc3ed6258370'
  PERMISSION_DENIED_ID = '1370e5b7-d4eb-4566-bb1d-7748ee6a1838'
  ROLE_DENIED = {
    moderator: ['You are not assigned to a moderator role', 'd33d5333-db36-423d-a8f9-1a2b9549da41'],
    admin: ['You are not assigned to an administrator role', 'c3d38592-54c0-429d-be96-5636b0431a61'],
    policy: ['You are not assigned to a required role', '7f86f06f-7e15-4057-8561-f4b6d4ac755a'],
  }.freeze

  Endpoint = Struct.new(:kind, :role, :permission, :secure, keyword_init: true)

  class_attribute :misskey_admin_endpoints, instance_writer: false, default: {}

  def self.misskey_admin_endpoint(*actions, kind:, permission:, role: :moderator, secure: false)
    endpoint = Endpoint.new(kind: kind, role: role, permission: permission, secure: secure)
    self.misskey_admin_endpoints = misskey_admin_endpoints.merge(actions.to_h { |action| [action.to_s, endpoint] }).freeze
  end

  before_action :require_misskey_admin!
  before_action :require_admin_object_body!

  rescue_from Mastodon::NotPermittedError do
    render_role_denied
  end

  private

  def misskey_admin_endpoint
    misskey_admin_endpoints.fetch(action_name)
  end

  def require_misskey_admin!
    return render_error('Credential required', 'CREDENTIAL_REQUIRED', 401, id: CREDENTIAL_REQUIRED_ID) if current_user.nil?
    return render_error('Your account has been suspended', 'YOUR_ACCOUNT_SUSPENDED', 403, id: SUSPENDED_ID, kind: 'permission') unless current_user.functional?
    return render_error(I18n.t('errors.403'), 'ACCESS_DENIED', 403, id: ACCESS_DENIED_ID) if misskey_admin_endpoint.secure && !native_user_token?
    return render_role_denied unless Array(misskey_admin_endpoint.permission).all? { |flag| current_user.role.can?(flag) }

    render_app_permission_denied unless admin_token_allowed?
  end

  def admin_token_allowed?
    return current_misskey_grant.native_user_token? || current_misskey_grant.allows?(misskey_admin_endpoint.kind) if current_misskey_grant

    scope = misskey_admin_endpoint.kind.to_s.start_with?('read:') ? 'admin:read' : 'admin:write'
    current_token.scopes.exists?(scope)
  end

  def render_role_denied
    message, id = ROLE_DENIED.fetch(misskey_admin_endpoint.role)
    render_error(message, 'ROLE_PERMISSION_DENIED', 403, id: id, kind: 'permission')
  end

  def render_app_permission_denied
    render_error('Your app does not have the necessary permissions to use this endpoint', 'PERMISSION_DENIED', 403, id: PERMISSION_DENIED_ID, kind: 'permission')
  end

  def require_admin_object_body!
    object_body!
  end

  def mi_id_param(key)
    value = params[key]
    value.is_a?(String) ? MisskeyCompat::MiId.decode(value) : nil
  end

  def mi_id_array_param(key)
    values = params[key]
    return nil unless values.is_a?(Array) && values.all?(String)

    values.map { |value| MisskeyCompat::MiId.decode(value) }
  end

  def boolean_param(key)
    value = params[key]
    [true, false].include?(value) ? value : nil
  end

  def require_keys!(*keys)
    missing = keys.find { |key| !params.key?(key) }
    return true if missing.nil?

    render_invalid_param('#/required', "must have required property '#{missing}'")
    false
  end

  def string_param?(key, nullable: false)
    value = params[key]
    value.is_a?(String) || (nullable && value.nil?)
  end

  def require_string_param!(key, nullable: false, min_length: 0)
    return true if string_param?(key, nullable: nullable) && (params[key].nil? || params[key].length >= min_length)

    render_invalid_param("#/properties/#{key}", min_length.positive? ? "must be a string of at least #{min_length} characters" : 'must be string')
    false
  end

  def require_boolean_param!(key)
    return true if !params.key?(key) || [true, false].include?(params[key])

    render_invalid_param("#/properties/#{key}", 'must be boolean')
    false
  end

  def require_integer_param!(key, required: false)
    return true if !required && !params.key?(key)
    return true if params[key].is_a?(Integer)

    render_invalid_param("#/properties/#{key}", 'must be integer')
    false
  end

  def require_string_array_param!(key, required: false)
    return true if !required && !params.key?(key)
    return true if params[key].is_a?(Array) && params[key].all?(String)

    render_invalid_param("#/properties/#{key}", 'must be array of strings')
    false
  end

  def paginate_admin_scope(scope, default: 10, max: 100)
    table = scope.klass.arel_table
    scope = scope.where(table[:id].lt(params[:untilId].to_i)) if params[:untilId].present?
    scope = scope.where(table[:id].gt(params[:sinceId].to_i)) if params[:sinceId].present?
    apply_compat_pagination_dates(scope).reorder(id: forward_pagination? ? :asc : :desc).limit(pagination_limit(default: default, max: max))
  end
end
