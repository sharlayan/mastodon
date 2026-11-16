# frozen_string_literal: true

class Api::MisskeyCompat::FlashController < Api::MisskeyCompat::BaseController
  NO_SUCH_FLASH_IDS = {
    'show' => 'f0d34a1a-d29a-401d-90ba-1982122b5630',
    'update' => '611e13d2-309e-419a-a5e4-e0422da39b02',
    'destroy' => 'de1623ef-bbb3-4289-a71e-14cfa83d9740',
    'like' => 'c07c1491-9161-4c5c-9d75-01906f911f73',
    'unlike' => 'afe8424a-a69e-432d-a5f2-2f0740c62410',
  }.freeze
  ACCESS_DENIED_IDS = {
    'update' => '08e60c88-5948-478e-a132-02ec701d67b2',
    'destroy' => '1036ad7b-9f92-4fff-89c3-0e50dc941704',
  }.freeze
  YOUR_FLASH_ID = '3fd8a0e7-5955-4ba9-85bb-bf3e0c30e13b'
  ALREADY_LIKED_ID = '010065cf-ad43-40df-8067-abff9f4686e3'
  NOT_LIKED_ID = '755f25a7-9871-4f65-9f34-51eaad9ae0ac'
  DEFAULT_LIMIT = 10
  SEARCH_DEFAULT_LIMIT = 5
  MAX_LIMIT = 100
  QUERY_LENGTH_LIMIT = 100
  OPTIONAL_AUTHENTICATION_ACTIONS = %i(featured search show by_user).freeze
  STRING_FIELDS = {
    title: MisskeyFlash::TITLE_LENGTH_LIMIT,
    summary: MisskeyFlash::SUMMARY_LENGTH_LIMIT,
    script: MisskeyFlash::SCRIPT_LENGTH_LIMIT,
  }.freeze

  requires_write_scope :create, :update, :destroy, :like, :unlike
  requires_misskey_permission 'read:account', *OPTIONAL_AUTHENTICATION_ACTIONS
  requires_misskey_permission 'read:flash', :mine
  requires_misskey_permission 'read:flash-likes', :likes
  requires_misskey_permission 'write:flash', :create, :update, :destroy
  requires_misskey_permission 'write:flash-likes', :like, :unlike

  before_action :require_user!, except: OPTIONAL_AUTHENTICATION_ACTIONS
  before_action :require_user_if_authenticated!, only: OPTIONAL_AUTHENTICATION_ACTIONS
  before_action :require_object_body!, only: [:create, :update]
  before_action :set_flash, only: [:show, :update, :destroy, :like, :unlike]

  def featured
    offset = offset_param
    return if offset.nil?

    render_flashes(MisskeyFlash.featured.includes(:account).offset(offset).limit(list_limit), current_account: current_account)
  end

  def search
    return unless valid_query?(:query, required: true)

    scope = MisskeyFlash.publicly_listed.includes(:account).matching(params[:query])
    render_flashes(apply_range(scope).limit(pagination_limit(default: SEARCH_DEFAULT_LIMIT, max: MAX_LIMIT)), current_account: current_account)
  end

  def by_user
    return render_invalid_param('#/properties/userId', 'must be a valid id') unless compat_id?(params[:userId])

    render_flashes(apply_range(MisskeyFlash.publicly_listed.includes(:account).where(account_id: params[:userId])).limit(list_limit))
  end

  def mine
    render_flashes(apply_range(MisskeyFlash.where(account: current_account).includes(:account)).limit(list_limit))
  end

  def likes
    return unless valid_query?(:search, required: false)

    scope = MisskeyFlashLike.where(account: current_account).joins(misskey_flash: :account).merge(Account.without_suspended)
    scope = scope.merge(MisskeyFlash.matching(params[:search])) unless params[:search].nil?
    likes = apply_range(scope).includes(misskey_flash: :account).limit(list_limit).to_a
    flashes = MisskeyCompat::FlashSerializer.serialize_many(likes.map(&:misskey_flash), current_account: current_account)
    render json: likes.zip(flashes).map { |like, item| { id: MisskeyCompat::MiId.encode(like.id), flash: item } }
  end

  def show
    render json: MisskeyCompat::FlashSerializer.serialize(@record, current_account: current_account)
  end

  def create
    return unless valid_flash_params?(create: true)
    return if rate_limited?(:misskey_flash_create)

    record = MisskeyFlash.create!(flash_attributes.merge(account: current_account))
    render json: MisskeyCompat::FlashSerializer.serialize(record)
  end

  def update
    return render_access_denied unless @record.account_id == current_account.id
    return unless valid_flash_params?(create: false)
    return if rate_limited?(:misskey_flash_update)

    @record.update!(flash_attributes.merge(updated_at: Time.current))
    head 204
  end

  def destroy
    return render_access_denied unless @record.account_id == current_account.id || current_user.can?(:manage_reports)

    @record.destroy!
    head 204
  end

  def like
    return render_error('You cannot like your flash', 'YOUR_FLASH', 400, id: YOUR_FLASH_ID) if @record.account_id == current_account.id
    return render_already_liked if @record.likes.exists?(account_id: current_account.id)

    @record.likes.create!(account: current_account)
    head 204
  rescue ActiveRecord::RecordNotUnique
    render_already_liked
  end

  def unlike
    like = @record.likes.find_by(account_id: current_account.id)
    return render_error('You have not liked that flash', 'NOT_LIKED', 400, id: NOT_LIKED_ID) if like.nil?

    like.destroy!
    head 204
  end

  private

  def set_flash
    @record = MisskeyFlash.available_accounts.includes(:account).find_by(id: params[:flashId]) if compat_id?(params[:flashId])
    render_error('No such flash', 'NO_SUCH_FLASH', 404, id: NO_SUCH_FLASH_IDS[action_name]) if @record.nil?
  end

  def render_access_denied
    render_error('Access denied', 'ACCESS_DENIED', 403, id: ACCESS_DENIED_IDS[action_name])
  end

  def render_already_liked
    render_error('The flash has already been liked', 'ALREADY_LIKED', 400, id: ALREADY_LIKED_ID)
  end

  def require_object_body!
    object_body!
  end

  def list_limit
    pagination_limit(default: DEFAULT_LIMIT, max: MAX_LIMIT)
  end

  def apply_range(scope)
    table = scope.klass.table_name
    scope = apply_compat_pagination_dates(scope)
    scope = scope.where("#{table}.id < ?", params[:untilId].to_i) if params[:untilId].present?
    scope = scope.where("#{table}.id > ?", params[:sinceId].to_i) if params[:sinceId].present?
    scope.reorder(Arel.sql("#{table}.id #{forward_pagination? ? 'ASC' : 'DESC'}"))
  end

  def valid_query?(key, required:)
    value = params[key]
    return true if !required && value.nil?
    return true if value.is_a?(String) && value.length.between?(1, QUERY_LENGTH_LIMIT)

    render_invalid_param("#/properties/#{key}", "must be a string of 1 to #{QUERY_LENGTH_LIMIT} characters")
    false
  end

  def valid_flash_params?(create:)
    STRING_FIELDS.each do |key, max|
      next if !create && !params.key?(key)
      next if params[key].is_a?(String) && params[key].length <= max

      render_invalid_param("#/properties/#{key}", "must be a string of at most #{max} characters")
      return false
    end

    valid_permissions?(required: create) && valid_visibility?
  end

  def valid_permissions?(required:)
    return true if !required && !params.key?(:permissions)

    value = params[:permissions]
    return true if value.is_a?(Array) && value.all? { |permission| permission.is_a?(String) && permission.length <= MisskeyFlash::PERMISSION_LENGTH_LIMIT }

    render_invalid_param('#/properties/permissions', 'must be an array of strings')
    false
  end

  def valid_visibility?
    return true if !params.key?(:visibility) || MisskeyFlash::VISIBILITIES.include?(params[:visibility])

    render_invalid_param('#/properties/visibility', "must be one of #{MisskeyFlash::VISIBILITIES.join(', ')}")
    false
  end

  def flash_attributes
    %i(title summary script permissions visibility).each_with_object({}) do |key, attributes|
      attributes[key] = params[key] if params.key?(key)
    end
  end

  def render_flashes(flashes, current_account: nil)
    render json: MisskeyCompat::FlashSerializer.serialize_many(flashes.to_a, current_account: current_account)
  end
end
