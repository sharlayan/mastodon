# frozen_string_literal: true

class Api::MisskeyCompat::AppsController < Api::MisskeyCompat::BaseController
  include Api::MisskeyCompat::CredentialConfirmation

  NO_SUCH_APP_ID = 'dce83913-2dc6-4093-8a7b-71dbb11718a3'
  LEGACY_PERMISSION_PATTERN = %r{\A(.+)(/|-)(read|write)\z}

  requires_misskey_permission 'read:account', :index

  before_action :require_object_body!
  before_action :require_user!, only: :index
  before_action :require_valid_credential!, only: [:create, :show]

  def index
    offset = offset_param
    return if offset.nil?

    applications = misskey_applications.where(owner: current_user).order(:id).offset(offset).limit(pagination_limit(default: 10, max: 100))
    render json: applications.map { |application| MisskeyCompat::AppSerializer.serialize(application, viewer: current_user) }
  end

  def show
    return unless require_string_params!(:appId)

    application = misskey_applications.find_by(id: params[:appId])
    return render_error('No such app.', 'NO_SUCH_APP', 404, id: NO_SUCH_APP_ID) if application.nil? # rubocop:disable I18n/RailsI18n/DecorateString

    include_secret = current_user.present? && native_user_token? && application.owner == current_user
    render json: MisskeyCompat::AppSerializer.serialize(application, viewer: current_user, include_secret: include_secret)
  end

  def create
    return unless require_string_params!(:name, :description, optional: [:callbackUrl]) && valid_permission_param?
    return if rate_limited?(:misskey_compat_api)

    application = Doorkeeper::Application.transaction do
      Doorkeeper::Application.create!(
        name: params[:name].truncate(ApplicationExtension::APP_NAME_LIMIT),
        redirect_uri: Doorkeeper.config.native_redirect_uri,
        scopes: MisskeyCompat::MiAuth::TOKEN_SCOPE,
        owner: current_user
      ).tap do |app|
        app.create_misskey_app!(description: params[:description], permission: converted_permissions, callback_url: params[:callbackUrl])
      end
    end

    render json: MisskeyCompat::AppSerializer.serialize(application, include_secret: true)
  end

  private

  def require_object_body!
    object_body!
  end

  def valid_permission_param?
    permission = params[:permission]

    if !permission.is_a?(Array) || !permission.all?(String)
      render_invalid_param(params.key?(:permission) ? '#/properties/permission/type' : '#/required', params.key?(:permission) ? 'must be array of strings' : "must have required property 'permission'")
      false
    elsif permission.uniq.size != permission.size
      render_invalid_param('#/properties/permission/uniqueItems', 'must NOT have duplicate items')
      false
    else
      true
    end
  end

  def converted_permissions
    params[:permission].map { |value| value.sub(LEGACY_PERMISSION_PATTERN, '\3:\1') }.uniq
  end
end
