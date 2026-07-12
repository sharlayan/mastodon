# frozen_string_literal: true

class Api::MisskeyCompat::ClipsController < Api::MisskeyCompat::BaseController
  requires_write_scope :create, :update, :destroy, :add_note, :remove_note, :favorite, :unfavorite

  OWNER_ACTIONS = %i(index create update destroy add_note remove_note my_favorites favorite unfavorite).freeze

  before_action :require_clips_enabled!
  before_action :require_user!, only: OWNER_ACTIONS
  before_action :set_clip, only: [:show, :update, :destroy, :add_note, :remove_note]
  before_action :authorize_owner!, only: [:update, :destroy, :add_note, :remove_note]

  def index
    render json: Clip.where(account: current_account).map { |clip| serialize(clip) }
  end

  def show
    render json: serialize(@clip)
  end

  def create
    clip = Clip.create!(clip_params.merge(account: current_account))
    render json: serialize(clip)
  rescue ActiveRecord::RecordInvalid => e
    render_error(e.to_s, 'INVALID_PARAM', 400)
  end

  def update
    @clip.update!(clip_params)
    render json: serialize(@clip)
  rescue ActiveRecord::RecordInvalid => e
    render_error(e.to_s, 'INVALID_PARAM', 400)
  end

  def destroy
    @clip.destroy!
    head 204
  end

  def add_note
    status = Status.find(params[:noteId])
    authorize status, :show?
    @clip.clip_statuses.find_or_create_by!(status: status)
    head 204
  rescue ActiveRecord::RecordNotFound, Mastodon::NotPermittedError
    render_error('No such note', 'NO_SUCH_NOTE', 404)
  end

  def remove_note
    @clip.clip_statuses.where(status_id: params[:noteId]).destroy_all
    head 204
  end

  def notes
    clip = Clip.find(params[:clipId])
    return render_error('No such clip', 'NO_SUCH_CLIP', 404) unless clip.visible_to?(current_account)

    statuses = visible_statuses(clip)
    Status.preload_cacheable_associations(statuses)
    context = MisskeyCompat::SerializationContext.for(statuses, current_account: current_account)
    render json: statuses.map { |status| MisskeyCompat::NoteSerializer.serialize(status, context: context) }
  rescue ActiveRecord::RecordNotFound
    render_error('No such clip', 'NO_SUCH_CLIP', 404)
  end

  def by_user
    account = Account.find(params[:userId])
    render json: account.clips.public_clips.map { |clip| serialize(clip) }
  rescue ActiveRecord::RecordNotFound
    render_error('No such user', 'NO_SUCH_USER', 404)
  end

  def favorite
    head 204
  end

  def unfavorite
    head 204
  end

  def my_favorites
    render json: []
  end

  private

  def require_clips_enabled!
    render_error('Clips are not available on this server', 'UNAVAILABLE', 400) unless Setting.clips_enabled
  end

  def set_clip
    @clip = Clip.find(params[:clipId])
    render_error('No such clip', 'NO_SUCH_CLIP', 404) unless @clip.visible_to?(current_account)
  rescue ActiveRecord::RecordNotFound
    render_error('No such clip', 'NO_SUCH_CLIP', 404)
  end

  def authorize_owner!
    render_error('Forbidden', 'ACCESS_DENIED', 403) unless @clip.account_id == current_account&.id
  end

  def visible_statuses(clip)
    statuses = clip.statuses.includes(:account).to_a
    return statuses if clip.account_id == current_account&.id

    statuses.select { |status| StatusPolicy.new(current_account, status).show? }
  end

  def clip_params
    {
      title: params[:name],
      description: params[:description],
      public: ActiveModel::Type::Boolean.new.cast(params[:isPublic]),
    }.compact
  end

  def serialize(clip)
    MisskeyCompat::ClipSerializer.serialize(clip, current_account: current_account)
  end
end
