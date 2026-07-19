# frozen_string_literal: true

class Api::MisskeyCompat::ApController < Api::MisskeyCompat::BaseController
  before_action :require_user!
  before_action :require_administrator!, only: :get

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

  def get
    uri = params[:uri].to_s
    return render_invalid_param('#/properties/uri', 'uri required') if uri.blank?
    return render_invalid_param('#/properties/uri', 'must be an HTTP(S) URL') unless http_uri?(uri)
    return if rate_limited?(:misskey_compat_ap_get)

    object = if TagManager.instance.local_url?(uri)
               serialize_local_object(ResolveURLService.new.call(uri, on_behalf_of: current_account))
             else
               ActivityPub::Dereferencer.new(uri, signature_actor: current_account).object
             end

    object.nil? ? render_error('No such object', 'NO_SUCH_OBJECT', 404) : render(json: object)
  rescue Mastodon::NotPermittedError
    render_error('Forbidden', 'ACCESS_DENIED', 403)
  rescue Mastodon::UnexpectedResponseError, Mastodon::HostValidationError, Mastodon::LengthValidationError, Addressable::URI::InvalidURIError, *Mastodon::HTTP_CONNECTION_ERRORS
    render_error('No such object', 'NO_SUCH_OBJECT', 404)
  end

  private

  def require_administrator!
    render_error('Administrator permission required', 'PERMISSION_DENIED', 403) unless current_user.can?(:administrator)
  end

  def http_uri?(uri)
    parsed = Addressable::URI.parse(uri)
    %w(http https).include?(parsed.scheme) && parsed.host.present? && parsed.userinfo.nil?
  rescue Addressable::URI::InvalidURIError
    false
  end

  def serialize_local_object(resource)
    serializer = case resource
                 when Status then ActivityPub::NoteSerializer
                 when Account then ActivityPub::ActorSerializer
                 end
    return if serializer.nil?

    ActiveModelSerializers::SerializableResource.new(resource, serializer: serializer, adapter: ActivityPub::Adapter).as_json
  end
end
