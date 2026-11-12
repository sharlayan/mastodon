# frozen_string_literal: true

class Api::MisskeyCompat::Admin::AdsController < Api::MisskeyCompat::Admin::ServerBaseController
  REQUIRED = %i(url memo place priority ratio expiresAt startsAt imageUrl dayOfWeek).freeze
  STRING_PARAMS = { url: 1, memo: 0, place: 0, priority: 0, imageUrl: 1 }.freeze
  INTEGER_PARAMS = %i(ratio expiresAt startsAt dayOfWeek).freeze
  NO_SUCH_AD_IDS = { 'update' => 'b7aa1727-1354-47bc-a182-3a9c3973d300', 'destroy' => 'ccac9863-3a03-416e-b899-8a64041118b1' }.freeze

  misskey_admin_endpoint :index, kind: 'read:admin:ad', permission: :manage_settings
  misskey_admin_endpoint :create, :update, :destroy, kind: 'write:admin:ad', permission: :manage_settings

  before_action :set_ad, only: [:update, :destroy]

  def index
    return unless require_boolean_param!(:publishing)

    scope = MisskeyAd.all
    scope = params[:publishing] ? scope.publishing : scope.not_publishing unless params[:publishing].nil?
    render json: paginate_admin_scope(scope).map { |record| serialize(record) }
  end

  def create
    return unless require_keys!(*REQUIRED) && valid_ad_params?

    ad = MisskeyAd.create!(ad_attributes)
    log_action :create, ad

    render json: serialize(ad)
  end

  def update
    return unless valid_ad_params?

    @ad.update!(ad_attributes)
    log_action :update, @ad

    head 204
  end

  def destroy
    @ad.destroy!
    log_action :destroy, @ad

    head 204
  end

  private

  def set_ad
    id = mi_id_param(:id)
    @ad = MisskeyAd.find_by(id: id) if id.present?
    render_error('No such ad', 'NO_SUCH_AD', 404, id: NO_SUCH_AD_IDS.fetch(action_name)) if @ad.nil?
  end

  def valid_ad_params?
    STRING_PARAMS.all? { |key, min| !params.key?(key) || require_string_param!(key, min_length: min) } &&
      INTEGER_PARAMS.all? { |key| require_integer_param!(key) } &&
      require_boolean_param!(:isSensitive) &&
      %i(expiresAt startsAt).all? { |key| !params.key?(key) || valid_time?(key) }
  end

  def valid_time?(key)
    compat_time(params[key])
    true
  rescue ArgumentError
    render_invalid_param("#/properties/#{key}", 'must be a valid date')
    false
  end

  def ad_attributes
    {
      url: params[:url],
      image_url: params[:imageUrl],
      memo: params[:memo],
      place: params[:place],
      priority: params[:priority],
      ratio: params[:ratio],
      day_of_week: params[:dayOfWeek],
      is_sensitive: params[:isSensitive],
      expires_at: params[:expiresAt].present? && params[:expiresAt].nonzero? ? Time.zone.at(params[:expiresAt] / 1000.0) : nil,
      starts_at: params[:startsAt].present? && params[:startsAt].nonzero? ? Time.zone.at(params[:startsAt] / 1000.0) : nil,
    }.compact
  end

  def serialize(record)
    {
      id: MisskeyCompat::MiId.encode(record.id),
      expiresAt: record.expires_at.iso8601(3),
      startsAt: record.starts_at.iso8601(3),
      dayOfWeek: record.day_of_week,
      isSensitive: record.is_sensitive,
      url: record.url,
      imageUrl: record.image_url,
      memo: record.memo,
      place: record.place,
      priority: record.priority,
      ratio: record.ratio,
    }
  end
end
