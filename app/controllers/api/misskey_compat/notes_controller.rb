# frozen_string_literal: true

class Api::MisskeyCompat::NotesController < Api::MisskeyCompat::BaseController
  requires_write_scope :unrenote, :thread_muting_create, :thread_muting_delete,
                       :reactions_create, :reactions_delete, :create, :update,
                       :scheduled_cancel, :destroy, :favorites_create,
                       :favorites_delete, :polls_vote

  USER_ACTIONS = %i(
    timeline hybrid_timeline mentions my_favorites
    create update destroy state search search_by_tag translate unrenote
    scheduled_list scheduled_cancel
    reactions_create reactions_delete
    thread_muting_create thread_muting_delete
    favorites_create favorites_delete polls_vote polls_recommendation
  ).freeze

  before_action :require_user!, only: USER_ACTIONS + %i(local_timeline global_timeline)
  before_action :set_note, only: [:show, :children, :replies, :conversation, :renotes, :unrenote, :destroy, :state, :translate, :reactions_create, :reactions_delete, :note_reactions, :thread_muting_create, :thread_muting_delete, :favorites_create, :favorites_delete, :polls_vote, :clips]

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
    return if current_account.nil? && rate_limited?(:misskey_compat_api)

    @note = MisskeyCompat::ThreadResolveService.new.call(@note, on_behalf_of: current_account)
    render json: serialize(@note)
  end

  def children
    scope = Status.where(in_reply_to_id: @note.id)
    render_visible_notes paginate_notes(scope)
  end

  def replies
    scope = Status.where(in_reply_to_id: @note.id)
    render_visible_notes paginate_notes(scope)
  end

  def conversation
    statuses = @note.ancestors(pagination_limit(default: 10, max: 100) + params[:offset].to_i, current_account).reverse
    statuses = statuses.drop(params[:offset].to_i).first(pagination_limit(default: 10, max: 100))
    Status.preload_cacheable_associations(statuses)
    preload_relations(statuses)
    render json: serialize_collection(statuses)
  end

  def renotes
    scope = Status.where(reblog_of_id: @note.id).where(text: [nil, ''])
    render_visible_notes paginate_notes(scope)
  end

  def unrenote
    Status.where(account_id: current_account.id, reblog_of_id: @note.id).find_each do |reblog|
      RemoveStatusService.new.call(reblog)
    end
    head 204
  end

  def note_reactions
    scope = @note.status_reactions.includes(:account, :custom_emoji).order(id: :desc)
    scope = scope.where(name: reaction_type_name(params[:type])) if params[:type].present?
    scope = scope.where(id: ...(until_id.to_i)) if until_id.present?
    scope = scope.where('status_reactions.id > ?', since_id.to_i) if since_id.present?
    reactions = scope.limit(pagination_limit(default: 10, max: 100))

    render json: reactions.map { |reaction| serialize_note_reaction(reaction) }
  end

  def thread_muting_create
    conversation = @note.conversation
    render_error('No such note', 'NO_SUCH_NOTE', 404) and return if conversation.nil?

    current_account.mute_conversation!(conversation)
    head 204
  end

  def thread_muting_delete
    conversation = @note.conversation
    render_error('No such note', 'NO_SUCH_NOTE', 404) and return if conversation.nil?

    current_account.unmute_conversation!(conversation)
    head 204
  end

  def state
    render json: {
      isFavorited: current_account.favourited?(@note),
      isMutedThread: @note.conversation.present? && current_account.muting_conversation?(@note.conversation),
      isRenoted: current_account.reblogged?(@note),
    }
  end

  def translate
    render_error('Translation is not available', 'UNAVAILABLE', 400) and return unless TranslationService.configured?

    translation = TranslateStatusService.new.call(@note, target_language)
    render json: { sourceLang: translation.detected_source_language, text: html_to_text(translation.content) }
  rescue TranslationService::NotConfiguredError, Mastodon::NotPermittedError
    render_error('Translation is not available', 'UNAVAILABLE', 400)
  rescue TranslationService::Error
    render_error('Translation failed', 'TRANSLATION_FAILED', 500)
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
    status = if renote_id.present? && params[:text].blank?
               ReblogService.new.call(current_account, quoted_status)
             else
               with_resolved_media_ids do |media_ids|
                 PostStatusService.new.call(current_account, post_options.merge(media_ids: media_ids))
               end
             end

    return render json: { scheduledNoteId: MisskeyCompat::MiId.encode(status.id) } if status.is_a?(ScheduledStatus)

    render json: { createdNote: serialize(status) }
  rescue ActiveRecord::RecordNotFound
    render_error('No such note', 'NO_SUCH_NOTE', 404)
  rescue Mastodon::NotPermittedError
    render_error('Forbidden', 'ACCESS_DENIED', 403)
  rescue MisskeyCompat::DriveFileResolver::NoSuchFileError
    render_error('No such file', 'NO_SUCH_FILE', 404)
  rescue MisskeyCompat::DriveFileResolver::AmbiguousFileError
    render_invalid_param('#/properties/fileIds', 'ambiguous file id')
  end

  def update
    note = Status.find_by(id: params[:noteId])
    render_error('No such note', 'NO_SUCH_NOTE', 404) and return if note.nil? || note.account_id != current_account.id

    with_resolved_media_ids(status: note) do |media_ids|
      UpdateStatusService.new.call(note, current_account.id, update_options.merge(media_ids: media_ids))
    end
    head 204
  rescue Mastodon::NotPermittedError
    render_error('Forbidden', 'ACCESS_DENIED', 403)
  rescue MisskeyCompat::DriveFileResolver::NoSuchFileError
    render_error('No such file', 'NO_SUCH_FILE', 404)
  rescue MisskeyCompat::DriveFileResolver::AmbiguousFileError
    render_invalid_param('#/properties/fileIds', 'ambiguous file id')
  end

  def scheduled_list
    scope = current_account.scheduled_statuses.includes(:media_attachments).order(id: :desc)
    scheduled = scope.limit(pagination_limit).offset(params[:offset].to_i).to_a

    render json: scheduled.map { |scheduled_status| serialize_scheduled(scheduled_status) }
  end

  def scheduled_cancel
    scheduled = current_account.scheduled_statuses.find_by(id: params[:draftId])
    render_error('No such note', 'NO_SUCH_NOTE', 404) and return if scheduled.nil?

    scheduled.destroy!
    head 204
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

  def search_by_tag
    tag = Tag.find_normalized(params[:tag].to_s)
    return render json: [] if tag.nil?

    statuses = TagFeed.new(tag, current_account, tag_feed_options).get(pagination_limit(default: 10, max: 100), until_id, since_id)
    statuses = statuses.reject(&:reply?) if params[:reply].to_s == 'false'
    render_notes statuses
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
    favourites = favourites.limit(pagination_limit).to_a

    statuses = favourites.map(&:status)
    Status.preload_cacheable_associations(statuses)
    preload_relations(statuses)
    context = MisskeyCompat::SerializationContext.for(statuses, current_account: current_account)

    render json: favourites.map { |fav|
      { id: MisskeyCompat::MiId.encode(fav.id), createdAt: fav.created_at.iso8601, noteId: MisskeyCompat::MiId.encode(fav.status_id), note: MisskeyCompat::NoteSerializer.serialize(fav.status, context: context) }
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

  def paginate_notes(scope)
    scope = scope.where(id: ...(until_id.to_i)) if until_id.present?
    scope = scope.where('statuses.id > ?', since_id.to_i) if since_id.present?
    scope.order(id: :desc).limit(pagination_limit(default: 10, max: 100))
  end

  def render_visible_notes(scope)
    statuses = scope.to_a.select { |status| StatusPolicy.new(current_account, status).show? }
    Status.preload_cacheable_associations(statuses)
    preload_relations(statuses)
    render json: serialize_collection(statuses)
  end

  def serialize_note_reaction(reaction)
    {
      id: MisskeyCompat::MiId.encode(reaction.id),
      createdAt: reaction.created_at.iso8601,
      user: MisskeyCompat::UserSerializer.serialize(reaction.account),
      type: reaction_type(reaction),
    }
  end

  def reaction_type(reaction)
    custom = reaction.custom_emoji
    return reaction.name if custom.nil?

    host = custom.domain.presence || '.'
    ":#{reaction.name}@#{host}:"
  end

  def reaction_type_name(type)
    name = type.to_s.delete_prefix(':').delete_suffix(':')
    host_separator = name.rindex('@')
    host_separator.nil? ? name : name[0...host_separator]
  end

  def target_language
    lang = params[:targetLang].to_s.presence || I18n.locale.to_s
    lang.split(/[_-]/).first
  end

  def html_to_text(html)
    Nokogiri::HTML5.fragment(html.to_s.gsub(%r{</p><p>}, "\n\n").gsub('<br>', "\n").gsub('<br/>', "\n")).text
  end

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
      text: composed_text(status_text),
      content_type: composed_content_type,
      spoiler_text: params[:cw].presence,
      visibility: mastodon_visibility(params[:visibility]),
      in_reply_to_id: params[:replyId].presence,
      local_only: ActiveModel::Type::Boolean.new.cast(params[:localOnly]),
      quoted_status: quoted,
      poll: poll_options,
      scheduled_at: scheduled_at_option,
    }.compact
  end

  def update_options
    {
      text: composed_text(params[:text].to_s),
      content_type: composed_content_type,
      spoiler_text: params[:cw].to_s,
    }
  end

  def with_resolved_media_ids(status: nil, &block)
    MisskeyCompat::DriveFileResolver.new.with_resolved(
      account: current_account,
      file_ids: params[:fileIds],
      status: status,
      allow_drive_files: Setting.drive_enabled,
      &block
    )
  end

  def composed_content_type
    mfm_composition_allowed? ? 'text/x-mfm' : 'text/markdown'
  end

  def composed_text(text)
    mfm_composition_allowed? ? text : MfmMarkdownConverter.convert(text)
  end

  def mfm_composition_allowed?
    Setting.mfm_enabled && Setting.mfm_allow_composition
  end

  def scheduled_at_option
    return nil if params[:scheduledAt].blank?

    Time.at(params[:scheduledAt].to_i / 1000.0).utc
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
    ids = Array(params[:visibleUserIds]).first(100).map(&:to_s).compact_blank
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

  def tag_feed_options
    {
      only_media: ActiveModel::Type::Boolean.new.cast(params[:withFiles]),
      local: params[:host].to_s == '.',
    }
  end

  def serialize(status)
    MisskeyCompat::NoteSerializer.serialize(status, current_account: current_account)
  end

  def serialize_scheduled(scheduled_status)
    params_hash = scheduled_status.params || {}

    {
      id: MisskeyCompat::MiId.encode(scheduled_status.id),
      updatedAt: scheduled_status.scheduled_at&.iso8601,
      scheduledAt: scheduled_status.scheduled_at&.iso8601,
      reason: nil,
      channel: nil,
      renote: nil,
      reply: nil,
      data: {
        text: params_hash['text'],
        useCw: params_hash['spoiler_text'].present?,
        cw: params_hash['spoiler_text'].presence,
        visibility: MisskeyCompat::NoteSerializer::VISIBILITY_MAP.fetch(params_hash['visibility'], 'public'),
        localOnly: ActiveModel::Type::Boolean.new.cast(params_hash['local_only']) || false,
        files: scheduled_status.media_attachments.map { |media| MisskeyCompat::DriveFileSerializer.serialize(media) },
        poll: nil,
        visibleUserIds: [],
      },
    }
  end

  def serialize_collection(statuses)
    context = MisskeyCompat::SerializationContext.for(statuses, current_account: current_account)
    statuses.map { |status| MisskeyCompat::NoteSerializer.serialize(status, context: context) }
  end

  def render_notes(statuses)
    statuses = statuses.to_a
    Status.preload_cacheable_associations(statuses)
    preload_relations(statuses)
    render json: serialize_collection(statuses)
  end

  def preload_relations(statuses)
    ActiveRecord::Associations::Preloader.new(records: statuses, associations: [:thread, { quote: :quoted_status }, { mentions: :account }]).call

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
