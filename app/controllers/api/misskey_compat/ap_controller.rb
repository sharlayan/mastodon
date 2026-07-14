# frozen_string_literal: true

class Api::MisskeyCompat::ApController < Api::MisskeyCompat::BaseController
  before_action :require_user!

  def show
    uri = params[:uri].to_s
    return render_invalid_param('#/properties/uri', 'uri required') if uri.blank?
    return if rate_limited?(:misskey_compat_api)

    resource = ResolveURLService.new.call(uri, on_behalf_of: current_account)

    case resource
    when Status
      render json: { type: 'Note', object: MisskeyCompat::NoteSerializer.serialize(resource, current_account: current_account) }
    when Account
      render json: { type: 'User', object: MisskeyCompat::UserSerializer.serialize(resource, detailed: true, viewer: current_account) }
    else
      render_error('No such object', 'NO_SUCH_OBJECT', 404)
    end
  rescue Mastodon::NotPermittedError
    render_error('Forbidden', 'ACCESS_DENIED', 403)
  end
end
