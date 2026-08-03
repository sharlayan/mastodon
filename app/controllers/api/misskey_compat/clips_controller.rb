# frozen_string_literal: true

class Api::MisskeyCompat::ClipsController < Api::MisskeyCompat::BaseController
  include Api::ClipNotesRateLimit

  requires_write_scope :create, :update, :destroy, :add_note, :remove_note, :favorite, :unfavorite
  requires_misskey_permission 'read:account', :index
  requires_misskey_permission 'write:account', :create, :update, :destroy, :add_note, :remove_note
  requires_misskey_permission 'read:clip-favorite', :my_favorites
  requires_misskey_permission 'write:clip-favorite', :favorite, :unfavorite

  OWNER_ACTIONS = %i(index create update destroy add_note remove_note my_favorites favorite unfavorite).freeze

  before_action :require_clips_enabled!
  before_action :require_user!, only: OWNER_ACTIONS
  before_action :set_clip, only: [:show, :update, :destroy, :add_note, :remove_note, :favorite]
  before_action :authorize_owner!, only: [:update, :destroy, :add_note, :remove_note]
  before_action :enforce_clip_notes_rate_limit!, only: [:notes]

  def index
    clips = Clip.where(account: current_account).includes(:account).to_a
    render json: serialize_many(clips)
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
    @clip.with_lock do
      @clip.clip_statuses.find_or_create_by!(status: status)
    end
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
    account = Account.without_requested_deletion.find(params[:userId])
    clips = account.clips.public_clips.includes(:account).to_a
    render json: serialize_many(clips)
  rescue ActiveRecord::RecordNotFound
    render_error('No such user', 'NO_SUCH_USER', 404)
  end

  def favorite
    return render_error('The clip has already been favorited', 'ALREADY_FAVORITED', 400) if current_account.clip_favourites.exists?(clip_id: @clip.id)

    FavouriteClipService.new.call(current_account, @clip)
    head 204
  end

  def unfavorite
    clip = Clip.find(params[:clipId])
    return render_error('You have not favorited the clip', 'NOT_FAVORITED', 400) unless current_account.clip_favourites.exists?(clip_id: clip.id)

    UnfavouriteClipService.new.call(current_account, clip)
    head 204
  rescue ActiveRecord::RecordNotFound
    render_error('No such clip', 'NO_SUCH_CLIP', 404)
  end

  def my_favorites
    clips = current_account.clip_favourites.visible_to(current_account).includes(clip: :account).map(&:clip)
    render json: serialize_many(clips)
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
    statuses = clip.statuses.includes(:account).reorder(id: :desc)
    statuses = statuses.where(id: ...params[:untilId]) if params[:untilId].present?
    statuses = statuses.where('statuses.id > ?', params[:sinceId]) if params[:sinceId].present?
    statuses = statuses.limit(Clip::STATUSES_LIMIT).to_a
    statuses = statuses.select { |status| StatusPolicy.new(current_account, status).show? } unless clip.account_id == current_account&.id

    statuses.first(pagination_limit)
  end

  def enforce_clip_notes_rate_limit!
    record_clip_notes_request!
  rescue Mastodon::RateLimitExceededError
    render_error(I18n.t('errors.429'), 'RATE_LIMIT_EXCEEDED', 429)
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

  def serialize_many(clips)
    relationships = ClipRelationshipsPresenter.new(clips, current_account&.id)
    clips.map { |clip| MisskeyCompat::ClipSerializer.serialize(clip, current_account: current_account, relationships: relationships) }
  end
end
