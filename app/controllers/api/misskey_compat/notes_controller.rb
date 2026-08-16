# frozen_string_literal: true

class Api::MisskeyCompat::NotesController < Api::MisskeyCompat::BaseController
  include Api::AccountRateLimit

  class NoSuchReplyTargetError < StandardError; end

  requires_write_scope :unrenote, :thread_muting_create, :thread_muting_delete,
                       :reactions_create, :reactions_delete, :create, :update,
                       :scheduled_cancel, :drafts_create, :drafts_update, :drafts_delete,
                       :destroy, :favorites_create,
                       :favorites_delete, :polls_vote

  requires_misskey_permission 'read:account', :timeline, :local_timeline, :hybrid_timeline, :global_timeline,
                              :mentions, :state, :search, :search_by_tag, :translate, :scheduled_list,
                              :drafts_list, :drafts_count, :polls_recommendation
  requires_misskey_permission 'read:favorites', :my_favorites
  requires_misskey_permission 'write:notes', :unrenote, :create, :update, :scheduled_cancel, :destroy
  requires_misskey_permission 'write:account', :thread_muting_create, :thread_muting_delete
  requires_misskey_permission 'write:account', :drafts_create, :drafts_update, :drafts_delete
  requires_misskey_permission 'write:reactions', :reactions_create, :reactions_delete
  requires_misskey_permission 'write:favorites', :favorites_create, :favorites_delete
  requires_misskey_permission 'write:votes', :polls_vote

  USER_ACTIONS = %i(
    timeline hybrid_timeline mentions my_favorites
    create update destroy state search search_by_tag translate unrenote
    scheduled_list scheduled_cancel drafts_list drafts_count drafts_create drafts_update drafts_delete
    reactions_create reactions_delete
    thread_muting_create thread_muting_delete
    favorites_create favorites_delete polls_vote polls_recommendation
  ).freeze

  before_action :require_user!, only: USER_ACTIONS + %i(local_timeline global_timeline)
  before_action :enforce_reaction_rate_limit!, only: %i(reactions_create reactions_delete)
  before_action :enforce_status_draft_rate_limit!, only: %i(drafts_list drafts_count drafts_create drafts_update drafts_delete)
  before_action :set_note, only: [:show, :children, :replies, :conversation, :renotes, :unrenote, :destroy, :state, :translate, :reactions_create, :reactions_delete, :note_reactions, :thread_muting_create, :thread_muting_delete, :favorites_create, :favorites_delete, :polls_vote, :clips]

  def timeline
    render_notes HomeFeed.new(current_account).get(timeline_pagination_limit, timeline_until_id, timeline_since_id, timeline_min_id)
  end

  def local_timeline
    render_notes public_feed(local: true).get(timeline_pagination_limit, timeline_until_id, timeline_since_id, timeline_min_id)
  end

  def hybrid_timeline
    render_notes public_feed(allow_local_only: true).get(timeline_pagination_limit, timeline_until_id, timeline_since_id, timeline_min_id)
  end

  def global_timeline
    render_notes public_feed.get(timeline_pagination_limit, timeline_until_id, timeline_since_id, timeline_min_id)
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
    scope = @note.status_reactions.joins(:account).merge(Account.without_suspended)
    scope = scope.merge(Account.not_excluded_by_account(current_account)) if current_account
    scope = scope.includes(:account, :custom_emoji).order(id: :desc)
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
               reaction_acceptance_option if params.key?(:reactionAcceptance)
               ReblogService.new.call(current_account, quoted_status)
             else
               with_resolved_media_ids do |media_ids|
                 PostStatusService.new.call(current_account, post_options.merge(media_ids: media_ids))
               end
             end

    return render json: { scheduledNoteId: MisskeyCompat::MiId.encode(status.id) } if status.is_a?(ScheduledStatus)

    render json: { createdNote: serialize(status) }
  rescue NoSuchReplyTargetError
    render_error('No such reply target', 'NO_SUCH_REPLY_TARGET', 404)
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

  def drafts_list
    scope = current_account.status_drafts.within_data_limit.includes(:media_attachments).order(id: :desc)
    scope = scope.where(id: ...(until_id.to_i)) if until_id.present?
    scope = scope.where('status_drafts.id > ?', since_id.to_i) if since_id.present?
    scope = scope.where(created_at: ...(Time.zone.at(params[:untilDate].to_i / 1000.0))) if params[:untilDate].present?
    scope = scope.where(created_at: (Time.zone.at(params[:sinceDate].to_i / 1000.0))..) if params[:sinceDate].present?
    scope = scope.none if ActiveModel::Type::Boolean.new.cast(params[:scheduled])
    drafts = scope.limit(pagination_limit(default: StatusDraft::LIST_LIMIT, max: StatusDraft::LIST_LIMIT)).to_a
    statuses_by_id = draft_reference_statuses(drafts)

    render json: drafts.map { |draft| serialize_draft(draft, statuses_by_id: statuses_by_id) }
  end

  def drafts_count
    render json: current_account.status_drafts.within_data_limit.count
  end

  def drafts_create
    return unless draft_references_valid?

    validate_draft_params!

    with_resolved_media_ids do |media_ids|
      draft = current_account.status_drafts.build(data: misskey_draft_data)
      save_draft_with_media!(draft, media_ids)
      render json: { createdDraft: serialize_draft(draft) }
    end
  rescue ActiveRecord::RecordInvalid => e
    render_draft_validation_error(e)
  rescue MisskeyCompat::DriveFileResolver::NoSuchFileError
    render_error('No such file', 'NO_SUCH_FILE', 404)
  rescue MisskeyCompat::DriveFileResolver::AmbiguousFileError
    render_invalid_param('#/properties/fileIds', 'ambiguous file id')
  end

  def drafts_update
    draft = current_account.status_drafts.find_by(id: params[:draftId])
    return render_error('No such draft', 'NO_SUCH_NOTE_DRAFT', 404) if draft.nil?
    return unless draft_references_valid?

    validate_draft_params!

    draft.data = misskey_draft_data(existing: draft.data)

    unless params.key?(:fileIds)
      current_account.with_lock { draft.save! }
      return render json: { updatedDraft: serialize_draft(draft) }
    end

    with_resolved_media_ids do |media_ids|
      save_draft_with_media!(draft, media_ids)
      render json: { updatedDraft: serialize_draft(draft) }
    end
  rescue MisskeyCompat::DriveFileResolver::NoSuchFileError
    render_error('No such file', 'NO_SUCH_FILE', 404)
  rescue MisskeyCompat::DriveFileResolver::AmbiguousFileError
    render_invalid_param('#/properties/fileIds', 'ambiguous file id')
  end

  def drafts_delete
    draft = current_account.status_drafts.find_by(id: params[:draftId])
    return render_error('No such draft', 'NO_SUCH_NOTE_DRAFT', 404) if draft.nil?

    draft.destroy!
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
    return render json: [] unless Setting.trends

    scope = Trends.statuses.query.allowed
    scope = scope.filtered_for(current_account) if current_account
    statuses = scope.limit(100).to_a
    statuses.select! { |status| status.id < until_id.to_i } if until_id.present?

    render_notes statuses.first(pagination_limit(default: 10, max: 100))
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
    scope = scope.where(id: ...params[:untilId].to_i) if params[:untilId].present?
    scope = scope.where('clips.id > ?', params[:sinceId].to_i) if params[:sinceId].present?
    clips = scope.includes(:account).order(id: :desc).limit(pagination_limit(max: 100)).to_a
    relationships = ClipRelationshipsPresenter.new(clips, current_account&.id)

    render json: clips.map { |clip| MisskeyCompat::ClipSerializer.serialize(clip, current_account: current_account, relationships: relationships) }
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

  def reply_status
    return @reply_status if defined?(@reply_status)

    reply_id = params[:replyId].presence
    return @reply_status = nil if reply_id.nil?

    status = Status.find_by(id: reply_id)
    raise NoSuchReplyTargetError if status.nil? || !StatusPolicy.new(current_account, status).reply?

    @reply_status = status
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
      thread: reply_status,
      local_only: ActiveModel::Type::Boolean.new.cast(params[:localOnly]),
      quoted_status: quoted,
      poll: poll_options,
      scheduled_at: scheduled_at_option,
      reaction_acceptance: reaction_acceptance_option,
    }.compact
  end

  def update_options
    options = {
      text: composed_text(params[:text].to_s),
      content_type: composed_content_type,
      spoiler_text: params[:cw].to_s,
    }
    options[:reaction_acceptance] = reaction_acceptance_option if params.key?(:reactionAcceptance)
    options
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

  def reaction_acceptance_option
    value = params[:reactionAcceptance]
    return nil if value.nil?

    raise ArgumentError, 'invalid reactionAcceptance' unless Sharlayan::Status::Reactions::REACTION_ACCEPTANCES.include?(value)

    value
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
        reactionAcceptance: params_hash['reaction_acceptance'],
        files: scheduled_status.media_attachments.map { |media| MisskeyCompat::DriveFileSerializer.serialize(media) },
        poll: nil,
        visibleUserIds: [],
      },
    }
  end

  def serialize_draft(draft, statuses_by_id: nil)
    MisskeyCompat::StatusDraftSerializer.serialize(draft, current_account: current_account, statuses_by_id: statuses_by_id)
  end

  def draft_reference_statuses(drafts)
    ids = drafts.flat_map { |draft| [draft.data['in_reply_to_id'], draft.data['quoted_status_id']] }.compact.uniq
    statuses = Status.where(id: ids).to_a
    Status.preload_cacheable_associations(statuses)
    ActiveRecord::Associations::Preloader.new(records: statuses, associations: :mentions).call
    statuses.index_by(&:id)
  end

  def validate_draft_params!
    raise ArgumentError, 'scheduled drafts are not supported' if ActiveModel::Type::Boolean.new.cast(params[:isActuallyScheduled])
    raise ArgumentError, 'text is too long' if params[:text].to_s.length > StatusLengthValidator.max_chars
    raise ArgumentError, 'cw is too long' if params[:cw].to_s.length > 100
    raise ArgumentError, 'too many files' if Array(params[:fileIds]).length > Status::MEDIA_ATTACHMENTS_LIMIT

    reaction_acceptance_option if params.key?(:reactionAcceptance)

    poll = params[:poll]
    return if poll.blank?

    choices = Array(poll[:choices])
    raise ArgumentError, 'invalid poll choices' if choices.length > PollOptionsValidator::MAX_OPTIONS || choices.any? { |choice| choice.blank? || choice.to_s.each_grapheme_cluster.count > PollOptionsValidator::MAX_OPTION_CHARS }
  end

  def draft_references_valid?
    {
      replyId: ['No such reply target', 'NO_SUCH_REPLY_TARGET'],
      renoteId: ['No such renote target', 'NO_SUCH_RENOTE_TARGET'],
    }.each do |key, (message, code)|
      next if params[key].blank?

      status = Status.find_by(id: params[key])
      next if status && StatusPolicy.new(current_account, status).show?

      render_error(message, code, 404)
      return false
    end

    true
  end

  def misskey_draft_data(existing: nil)
    data = existing&.deep_dup || {
      'status' => nil,
      'spoiler_text' => nil,
      'content_type' => composed_content_type,
      'local_only' => false,
      'sensitive' => false,
      'visibility' => 'public',
      'visible_user_ids' => [],
    }

    data['status'] = params[:text] if params.key?(:text)
    data['spoiler_text'] = params[:cw] if params.key?(:cw)
    data['content_type'] = composed_content_type if params.key?(:text)
    data['local_only'] = ActiveModel::Type::Boolean.new.cast(params[:localOnly]) if params.key?(:localOnly)
    data['in_reply_to_id'] = params[:replyId].presence if params.key?(:replyId)
    data['visibility'] = mastodon_visibility(params[:visibility]) if params.key?(:visibility)
    data['visible_user_ids'] = Array(params[:visibleUserIds]).first(100) if params.key?(:visibleUserIds)
    data['poll'] = poll_options if params.key?(:poll)
    data['quoted_status_id'] = params[:renoteId].presence if params.key?(:renoteId)
    data['reaction_acceptance'] = params[:reactionAcceptance] if params.key?(:reactionAcceptance)
    data['scheduled_at'] = params[:scheduledAt].present? ? scheduled_at_option.iso8601 : nil if params.key?(:scheduledAt)
    data.compact
  end

  def save_draft_with_media!(draft, media_ids)
    ids = Array(media_ids).map(&:to_i)

    current_account.with_lock do
      draft.save!
      media = current_account.media_attachments.where(status_id: nil, scheduled_status_id: nil)
        .where(status_draft_id: [nil, draft.id]).where(id: ids).index_by(&:id)
      raise MisskeyCompat::DriveFileResolver::NoSuchFileError unless ids.all? { |id| media.key?(id) }

      draft.media_attachments.where.not(id: ids).update_all(status_draft_id: nil)
      ids.each { |id| media.fetch(id).update!(status_draft: draft) }
    end
  end

  def render_draft_validation_error(error)
    code = error.record.errors.include?(:data) ? 'DRAFT_TOO_LARGE' : 'TOO_MANY_DRAFTS'
    render_error(error.record.errors.full_messages.first, code, 400)
  end

  def enforce_status_draft_rate_limit!
    rate_limited?(:status_drafts)
  end

  def enforce_reaction_rate_limit!
    enforce_account_rate_limit!(:status_reactions)
  rescue Mastodon::RateLimitExceededError
    render_error(I18n.t('errors.429'), 'RATE_LIMIT_EXCEEDED', 429)
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

  def timeline_pagination_limit
    pagination_limit(max: 100)
  end

  def timeline_until_id
    until_id || snowflake_id_at(params[:untilDate])
  end

  def timeline_since_id
    timeline_until_id.present? ? timeline_since_boundary : nil
  end

  def timeline_min_id
    timeline_until_id.blank? ? timeline_since_boundary : nil
  end

  def timeline_since_boundary
    since_id || snowflake_id_at(params[:sinceDate])
  end

  def snowflake_id_at(value)
    Mastodon::Snowflake.id_at(compat_time(value), with_random: false) if value.present?
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
