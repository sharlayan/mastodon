# frozen_string_literal: true

class Api::MisskeyCompat::TokensController < Api::MisskeyCompat::BaseController
  include Redisable
  include Api::MisskeyCompat::CredentialConfirmation

  APPS_SORTS = {
    '+createdAt' => { id: :desc },
    '-createdAt' => { id: :asc },
    '+lastUsedAt' => Arel.sql('oauth_access_tokens.last_used_at DESC NULLS LAST'),
    '-lastUsedAt' => Arel.sql('oauth_access_tokens.last_used_at ASC NULLS FIRST'),
  }.freeze

  requires_write_scope :revoke, :regenerate, :gen_token
  requires_misskey_permission 'read:account', :index, :authorized_apps
  requires_misskey_permission 'write:account', :revoke, :regenerate, :gen_token

  before_action :require_object_body!
  before_action :require_user!
  before_action :require_native_user_token!

  def index
    sort = params[:sort]
    return render_invalid_param('#/properties/sort/enum', 'must be equal to one of the allowed values') unless sort.nil? || APPS_SORTS.key?(sort)

    tokens = app_tokens.includes(:misskey_access_grant, application: :misskey_app).reorder(APPS_SORTS.fetch(sort, { id: :asc })).select(&:accessible?)
    render json: tokens.map { |token| serialize_token(token) }
  end

  def authorized_apps
    offset = offset_param
    return if offset.nil?
    return render_invalid_param('#/properties/sort/enum', 'must be equal to one of the allowed values') unless params[:sort].nil? || %w(desc asc).include?(params[:sort])

    tokens = app_tokens.joins(application: :misskey_app).includes(application: :misskey_app).reorder(id: params[:sort] == 'asc' ? :asc : :desc)
    tokens = tokens.offset(offset).limit(pagination_limit(default: 10, max: 100))
    render json: tokens.map { |token| MisskeyCompat::AppSerializer.serialize(token.application, viewer: current_user) }
  end

  def revoke
    token = if params.key?(:tokenId)
              params[:tokenId].is_a?(String) ? app_tokens.find_by(id: params[:tokenId]) : nil
            elsif params[:token].is_a?(String)
              app_tokens.find_by(token: params[:token])
            end

    revoke_token!(token) if token
    head 204
  end

  def regenerate
    return unless require_string_params!(:password)
    return unless confirm_credentials!(params[:password], second_factor: false)

    user_tokens.where(misskey_access_grants: { native_user_token: true }).find_each { |token| revoke_token!(token) }
    head 204
  end

  def gen_token
    return unless require_string_params!(optional: [:session, :name, :description, :iconUrl]) && valid_gen_token_params?
    return if rate_limited?(:misskey_miauth_hourly) || rate_limited?(:misskey_miauth_daily)

    token = MisskeyCompat::MiAuth.issue_token(current_user, permissions: params[:permission], name: params[:name], description: params[:description], icon_url: params[:iconUrl])

    session = params[:session]
    with_redis { |r| r.set(MisskeyCompat::MiAuth.redis_key(session), token.token, ex: MisskeyCompat::MiAuth::SESSION_TTL.to_i) } if MisskeyCompat::MiAuth.valid_session?(session)

    render json: { token: token.token }
  end

  private

  def require_object_body!
    object_body!
  end

  def user_tokens
    Doorkeeper::AccessToken.not_revoked.where(resource_owner_id: current_user.id).joins(:misskey_access_grant)
  end

  def app_tokens
    user_tokens.where(misskey_access_grants: { native_user_token: false })
  end

  def revoke_token!(token)
    token.revoke
    Web::PushSubscription.where(access_token_id: token.id).delete_all
  end

  def valid_gen_token_params?
    permission = params[:permission]

    if !params.key?(:session) || !params.key?(:permission)
      render_invalid_param('#/required', "must have required property '#{params.key?(:session) ? 'permission' : 'session'}'")
    elsif !permission.is_a?(Array) || !permission.all?(String) || permission.uniq.size != permission.size
      render_invalid_param('#/properties/permission', 'must be array of unique strings')
    else
      return true
    end

    false
  end

  def serialize_token(token)
    grant = token.misskey_access_grant
    misskey_app = token.application&.misskey_app

    {
      id: MisskeyCompat::MiId.encode(token.id),
      name: grant.name || (misskey_app ? token.application.name : MisskeyCompat::MiAuth.display_name(token.application)),
      createdAt: token.created_at.iso8601,
      permission: misskey_app ? misskey_app.permission : grant.permissions,
      iconUrl: grant.icon_url,
      description: grant.description || misskey_app&.description,
    }.tap do |data|
      data[:lastUsedAt] = token.last_used_at.iso8601 if token.last_used_at
    end
  end
end
