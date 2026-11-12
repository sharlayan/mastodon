# frozen_string_literal: true

class Api::MisskeyCompat::AuthSessionsController < Api::MisskeyCompat::BaseController
  include Api::MisskeyCompat::CredentialConfirmation

  NO_SUCH_APP_IDS = {
    'generate' => '92f93e63-428e-4f2f-a5a4-39e1407fe998',
    'userkey' => 'fcab192a-2c5a-43b7-8ad8-9b7054d8d40d',
  }.freeze

  NO_SUCH_SESSION_IDS = {
    'show' => 'bd72c97d-eba7-4adb-a467-f171b8847250',
    'userkey' => '5b5a1503-8bc8-4bd0-8054-dc189e8cdcb3',
    'accept' => '9c72d8de-391a-43c1-9d06-08d29efde8df',
  }.freeze

  PENDING_SESSION_ID = '8c8a4145-02cc-4cca-8e66-29ba60445a8e'

  requires_write_scope :accept
  requires_misskey_permission 'write:account', :accept

  before_action :require_object_body!
  before_action :require_user!, only: :accept
  before_action :require_native_user_token!, only: :accept
  before_action :require_valid_credential!, except: :accept
  before_action :enforce_rate_limit!, except: :accept

  def show
    return unless require_string_params!(:token)

    session = MisskeyAuthSession.active.includes(application: :misskey_app).find_by(token: params[:token])
    return no_such_session if session.nil?

    render json: {
      id: MisskeyCompat::MiId.encode(session.id),
      app: MisskeyCompat::AppSerializer.serialize(session.application, viewer: current_user),
      token: session.token,
    }
  end

  def generate
    return unless require_string_params!(:appSecret)

    application = misskey_applications.find_by(secret: params[:appSecret])
    return no_such_app if application.nil?

    MisskeyAuthSession.expired.where(application: application).delete_all
    session = MisskeyAuthSession.create!(application: application)

    render json: { token: session.token, url: misskey_auth_session_url(session.token) }
  end

  def userkey
    return unless require_string_params!(:appSecret, :token)

    application = misskey_applications.find_by(secret: params[:appSecret])
    return no_such_app if application.nil?

    session = MisskeyAuthSession.active.find_by(token: params[:token], application: application)
    return no_such_session if session.nil?
    return render_error('This session is not completed yet.', 'PENDING_SESSION', 400, id: PENDING_SESSION_ID) if session.user.nil? # rubocop:disable I18n/RailsI18n/DecorateString

    user = session.user
    access_token = MisskeyCompat::MiAuth.issue_app_token(user, application)
    session.destroy!

    render json: { accessToken: access_token, user: MisskeyCompat::UserSerializer.serialize(user.account, detailed: true) }
  end

  def accept
    return unless require_string_params!(:token)

    session = MisskeyAuthSession.active.joins(application: :misskey_app).find_by(token: params[:token])
    return no_such_session if session.nil?

    session.update!(user: current_user)
    head 204
  end

  private

  def require_object_body!
    object_body!
  end

  def enforce_rate_limit!
    rate_limited?(:misskey_compat_api)
  end

  def no_such_app
    render_error('No such app.', 'NO_SUCH_APP', 404, id: NO_SUCH_APP_IDS.fetch(action_name)) # rubocop:disable I18n/RailsI18n/DecorateString
  end

  def no_such_session
    render_error('No such session.', 'NO_SUCH_SESSION', 404, id: NO_SUCH_SESSION_IDS.fetch(action_name)) # rubocop:disable I18n/RailsI18n/DecorateString
  end
end
