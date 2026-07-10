# frozen_string_literal: true

class Api::MisskeyCompat::NotesController < Api::MisskeyCompat::BaseController
  USER_ACTIONS = %i(
    timeline hybrid_timeline mentions my_favorites
    create destroy state search
    reactions_create reactions_delete
    favorites_create favorites_delete polls_vote polls_recommendation
  ).freeze

  before_action :require_user!, only: USER_ACTIONS
  before_action :set_note, only: [:show, :children, :destroy, :state, :reactions_create, :reactions_delete, :favorites_create, :favorites_delete, :polls_vote, :clips]

  def timeline
    render_notes HomeFeed.new(current_account).get(pagination_limit, until_id, since_id)
  end

  def local_timeline
    render_notes public_feed(local: true).get(pagination_limit, until_id, since_id)
  end

  def hybrid_timeline
    render_notes public_feed(allow_local_only: true).get(pagination_limit, until_id, since_id)
  end

  def global_timeline
    render_notes public_feed.get(pagination_limit, until_id, since_id)
  end

  def show
    render json: serialize(@note)
  end

  def children
    descendants = @note.descendants(pagination_limit, current_account)
    render json: descendants.map { |status| serialize(status) }
  end

  def state
    render json: {
      isFavorited: current_account.favourited?(@note),
      isMutedThread: false,
      isRenoted: current_account.reblogged?(@note),
    }
  end

  def reactions_create
    reaction = params[:reaction].to_s
    render_error('reaction required', 'INVALID_PARAM', 400) and return if reaction.blank?

    result = ReactService.new.call(current_account, @note, normalize_reaction(reaction))
    render_error('Reaction could not be registered', 'REACTION_FAILED', 400) and return unless result.is_a?(StatusReaction) && result.persisted?

    head 204
  end

  def reactions_delete
    existing = @note.status_reactions.where(account: current_account).first
    UnreactService.new.call(current_account, @note, reaction_key(existing)) if existing
    head 204
  end

  def create
    status =
      if renote_id.present? && params[:text].blank?
        ReblogService.new.call(current_account, quoted_status)
      else
        PostStatusService.new.call(current_account, post_options)
      end

    render json: { createdNote: serialize(status) }
  rescue ActiveRecord::RecordNotFound
    render_error('No such note', 'NO_SUCH_NOTE', 404)
  rescue Mastodon::NotPermittedError
    render_error('Forbidden', 'ACCESS_DENIED', 403)
  end

  def destroy
    render_error('Forbidden', 'ACCESS_DENIED', 403) and return unless @note.account_id == current_account.id

    RemoveStatusService.new.call(@note)
    head 204
  end

  def mentions
    scope = Status.joins(:mentions).where(mentions: { account_id: current_account.id }).distinct
    render_notes scope.to_a_paginated_by_id(pagination_limit, max_id: until_id, since_id: since_id)
  end

  def featured
    render_notes public_feed(local: true).get(pagination_limit, until_id, since_id)
  end

  def search
    query = params[:query].to_s.strip
    return render json: [] if query.length < 2
    return if rate_limited?(:misskey_compat_api)

    like = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    scope = Status.where(visibility: [:public, :unlisted])
      .not_excluded_by_account(current_account)
      .where('statuses.text ILIKE ?', like)
    render_notes scope.to_a_paginated_by_id(pagination_limit, max_id: until_id, since_id: since_id)
  end

  def favorites_create
    FavouriteService.new.call(current_account, @note)
    head 204
  end

  def favorites_delete
    UnfavouriteService.new.call(current_account, @note)
    head 204
  end

  def my_favorites
    favourites = current_account.favourites.includes(status: :account).order(id: :desc)
    favourites = favourites.where(id: ...(until_id.to_i)) if until_id.present?
    favourites = favourites.where('favourites.id > ?', since_id.to_i) if since_id.present?
    favourites = favourites.limit(pagination_limit)

    render json: favourites.map { |fav|
      { id: fav.id.to_s, createdAt: fav.created_at.iso8601, noteId: fav.status_id.to_s, note: serialize(fav.status) }
    }
  end

  def clips
    scope = Clip.public_clips.joins(:clip_statuses).where(clip_statuses: { status_id: @note.id })
    render json: scope.map { |clip| MisskeyCompat::ClipSerializer.serialize(clip, current_account: current_account) }
  end

  def polls_recommendation
    scope = Status.where(visibility: [:public, :unlisted])
      .where.not(poll_id: nil)
      .joins(:poll)
      .where('polls.expires_at IS NULL OR polls.expires_at > ?', Time.now.utc)
      .not_excluded_by_account(current_account)
      .where.not(account_id: current_account.id)
      .order(id: :desc)
      .offset(params[:offset].to_i)
      .limit(pagination_limit)

    render_notes scope
  end

  def polls_vote
    poll = @note.preloadable_poll
    render_error('No such poll', 'NO_POLL', 404) and return if poll.nil?

    VoteService.new.call(current_account, poll, [params[:choice].to_i])
    head 204
  end

  private

  def renote_id
    params[:renoteId].presence
  end

  def quoted_status
    return @quoted_status if defined?(@quoted_status)

    @quoted_status = renote_id.present? ? Status.find(renote_id) : nil
    authorize(@quoted_status, :show?) if @quoted_status
    @quoted_status
  end

  def post_options
    quoted = quoted_status

    {
      text: status_text,
      spoiler_text: params[:cw].presence,
      visibility: mastodon_visibility(params[:visibility]),
      in_reply_to_id: params[:replyId].presence,
      media_ids: Array(params[:fileIds]).map(&:to_s).presence,
      local_only: ActiveModel::Type::Boolean.new.cast(params[:localOnly]),
      quoted_status: quoted,
      poll: poll_options,
    }.compact
  end

  def poll_options
    poll = params[:poll]
    return nil if poll.blank?

    {
      options: Array(poll[:choices]),
      expires_in: poll[:expiredAfter].presence || 86_400,
      multiple: ActiveModel::Type::Boolean.new.cast(poll[:multiple]),
    }
  end

  def mastodon_visibility(visibility)
    { 'public' => 'public', 'home' => 'unlisted', 'followers' => 'private', 'specified' => 'direct' }.fetch(visibility.to_s, 'public')
  end

  def status_text
    text = params[:text].to_s
    return text unless mastodon_visibility(params[:visibility]) == 'direct'

    prefix = specified_mention_prefix(text)
    prefix.present? ? "#{prefix} #{text}".strip : text
  end

  def specified_mention_prefix(text)
    ids = Array(params[:visibleUserIds]).map(&:to_s).compact_blank
    return '' if ids.empty?

    Account.where(id: ids).filter_map do |account|
      token = "@#{account.acct}"
      token unless text.match?(/#{Regexp.escape(token)}(?![\w@.-])/i)
    end.join(' ')
  end

  def set_note
    @note = Status.find(params[:noteId])
    authorize @note, :show?
  rescue ActiveRecord::RecordNotFound, Mastodon::NotPermittedError
    render_error('No such note', 'NO_SUCH_NOTE', 404)
  end

  def public_feed(**options)
    PublicFeed.new(current_account, { with_replies: true, with_reblogs: true }.merge(options))
  end

  def serialize(status)
    MisskeyCompat::NoteSerializer.serialize(status, current_account: current_account)
  end

  def render_notes(statuses)
    statuses = statuses.to_a
    Status.preload_cacheable_associations(statuses)
    preload_relations(statuses)
    render json: statuses.map { |status| serialize(status) }
  end

  def preload_relations(statuses)
    ActiveRecord::Associations::Preloader.new(records: statuses, associations: [:thread, { quote: :quoted_status }]).call

    related = statuses.filter_map(&:thread) + statuses.filter_map { |status| status.quote&.quoted_status }
    Status.preload_cacheable_associations(related) if related.any?
  end

  def until_id
    params[:untilId].presence
  end

  def since_id
    params[:sinceId].presence
  end

  def normalize_reaction(reaction)
    reaction = reaction[1..-2] if reaction.start_with?(':') && reaction.end_with?(':')
    reaction.delete_suffix('@.')
  end

  def reaction_key(reaction)
    custom = reaction.custom_emoji
    return reaction.name if custom.nil?

    custom.domain.present? ? "#{reaction.name}@#{custom.domain}" : reaction.name
  end
end
