# frozen_string_literal: true

class Api::MisskeyCompat::Admin::AvatarDecorationsController < Api::MisskeyCompat::Admin::ServerBaseController
  include RoutingHelper

  misskey_admin_endpoint :index, kind: 'read:admin:avatar-decorations', role: :policy, permission: :manage_custom_emojis
  misskey_admin_endpoint :create, :update, :destroy, kind: 'write:admin:avatar-decorations', role: :policy, permission: :manage_custom_emojis

  before_action :set_decoration, only: [:update, :destroy]

  def index
    authorize :avatar_decoration, :index?

    decorations = AvatarDecoration.local.includes(:category).order(id: :desc)
    render json: decorations.map { |decoration| serialize(decoration) }
  end

  def create
    authorize :avatar_decoration, :create?
    return unless require_keys!(:name, :description, :url) && valid_decoration_params?(create: true)

    decoration = AvatarDecoration.new(approved: true, **decoration_attributes)
    return unless assign_image(decoration)

    decoration.save!
    log_action :create, decoration

    render json: serialize(decoration).merge(updatedAt: nil)
  end

  def update
    authorize @decoration, :update?
    raise Mastodon::NotPermittedError unless @decoration.local?
    return unless valid_decoration_params?(create: false)

    @decoration.assign_attributes(decoration_attributes)
    return if params.key?(:url) && params[:url] != serialize(@decoration)[:url] && !assign_image(@decoration)

    @decoration.save!
    log_action :update, @decoration

    head 204
  end

  def destroy
    authorize @decoration, :destroy?

    @decoration.destroy!
    log_action :destroy, @decoration

    head 204
  end

  private

  def set_decoration
    id = mi_id_param(:id)
    @decoration = AvatarDecoration.find_by(id: id) if id.present?
    render_error('No such avatar decoration', 'NO_SUCH_AVATAR_DECORATION', 404) if @decoration.nil?
  end

  def valid_decoration_params?(create:)
    return false if params.key?(:name) && !require_string_param!(:name, min_length: 1)
    return false if params.key?(:description) && !require_string_param!(:description)
    return false if params.key?(:url) && !require_string_param!(:url, min_length: 1)
    return false if params.key?(:category) && !require_string_param!(:category, nullable: true)
    return false unless require_string_array_param!(:roleIdsThatCanBeUsedThisDecoration)
    return true if !create && !params.key?(:roleIdsThatCanBeUsedThisDecoration)

    role_ids = Array(params[:roleIdsThatCanBeUsedThisDecoration])
    return true if role_ids.empty? || (role_ids.one? && required_role.present?)

    render_invalid_param('#/properties/roleIdsThatCanBeUsedThisDecoration', 'must contain at most one existing role')
    false
  end

  def required_role
    return @required_role if defined?(@required_role)

    @required_role = UserRole.find_by(id: MisskeyCompat::MiId.decode(params[:roleIdsThatCanBeUsedThisDecoration].first))
  end

  def decoration_attributes
    attributes = { name: params[:name], description: params[:description] }.compact
    attributes[:required_role_id] = Array(params[:roleIdsThatCanBeUsedThisDecoration]).empty? ? nil : required_role.id if params.key?(:roleIdsThatCanBeUsedThisDecoration)
    attributes[:category_id] = params[:category].blank? ? nil : AvatarDecorationCategory.find_or_create_by!(name: params[:category]).id if params.key?(:category)
    attributes
  end

  def assign_image(decoration)
    decoration.image_remote_url = params[:url]
    decoration.download_image!
    return true if decoration.image_file_name.present? && decoration.errors.empty?

    render_invalid_param('#/properties/url', 'must be a reachable image URL')
    false
  end

  def serialize(decoration)
    {
      id: MisskeyCompat::MiId.encode(decoration.id),
      createdAt: decoration.created_at.iso8601,
      updatedAt: decoration.updated_at&.iso8601,
      name: decoration.name,
      description: decoration.description.to_s,
      url: full_asset_url(decoration.image_url),
      roleIdsThatCanBeUsedThisDecoration: decoration.required_role_id ? [MisskeyCompat::MiId.encode(decoration.required_role_id)] : [],
      category: decoration.category&.name,
    }
  end
end
