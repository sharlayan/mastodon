# frozen_string_literal: true

class Api::MisskeyCompat::Admin::RelaysController < Api::MisskeyCompat::Admin::ServerBaseController
  include RoleplayModeHelper

  STATUSES = { 'idle' => 'requesting', 'pending' => 'requesting', 'accepted' => 'accepted', 'paused' => 'accepted', 'rejected' => 'rejected' }.freeze

  misskey_admin_endpoint :index, kind: 'read:admin:relays', permission: :manage_federation
  misskey_admin_endpoint :create, :destroy, kind: 'write:admin:relays', permission: :manage_federation

  before_action :require_relays_available!

  def index
    authorize :relay, :update?

    render json: Relay.order(:id).map { |relay| serialize(relay) }
  end

  def create
    authorize :relay, :update?
    return render_invalid_url unless https_url?(params[:inbox])

    relay = Relay.create!(inbox_url: params[:inbox])
    log_action :create, relay
    relay.enable!

    render json: serialize(relay)
  end

  def destroy
    authorize :relay, :update?
    return unless require_string_param!(:inbox)

    relay = Relay.find_by(inbox_url: params[:inbox].strip)
    return render_error('No such relay', 'NO_SUCH_RELAY', 404) if relay.nil?

    relay.destroy!
    log_action :destroy, relay

    head 204
  end

  private

  def require_relays_available!
    render_error('Relays are not available on this server', 'UNAVAILABLE', 400) if roleplay_mode?
  end

  def https_url?(value)
    value.is_a?(String) && Addressable::URI.parse(value).then { |uri| uri.scheme == 'https' && uri.host.present? }
  rescue Addressable::URI::InvalidURIError
    false
  end

  def render_invalid_url
    render_error('Invalid URL', 'INVALID_URL', 400, id: 'fb8c92d3-d4e5-44e7-b3d4-800d5cef8b2c')
  end

  def serialize(relay)
    {
      id: MisskeyCompat::MiId.encode(relay.id),
      inbox: relay.inbox_url,
      status: STATUSES.fetch(relay.state, 'requesting'),
    }
  end
end
