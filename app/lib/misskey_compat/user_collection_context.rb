# frozen_string_literal: true

class MisskeyCompat::UserCollectionContext
  attr_reader :relationships

  def self.for(accounts, viewer: nil)
    new(accounts, viewer: viewer)
  end

  def initialize(accounts, viewer: nil)
    @accounts = Array(accounts).compact
    @viewer = viewer
    @account_ids = @accounts.map(&:id).uniq
    @instance_cache = {}
    preload_accounts
    preload_avatar_decorations
    preload_pinned_notes
    preload_pinned_pages
    @relationships = AccountRelationshipsPresenter.new(@accounts, viewer.id) if viewer
  end

  def avatar_decoration_configs_for(account)
    @avatar_decorations.fetch(account.id, [])
  end

  def pinned_notes_for(account)
    @pinned_notes.fetch(account.id, [[], []])
  end

  def pinned_page_for(account)
    page = @pinned_pages[account.id]
    return [nil, nil] if page.nil?

    [MisskeyCompat::MiId.encode(page.id), MisskeyCompat::PageSerializer.serialize(page, current_account: @viewer, collection: @pinned_pages_context)]
  end

  def instance_info(domain)
    return @instance_cache[domain] if @instance_cache.key?(domain)

    @instance_cache[domain] = yield
  end

  private

  def preload_accounts
    ActiveRecord::Associations::Preloader.new(records: @accounts, associations: [:account_stat, :moved_to_account, { user: :role }]).call
  end

  def preload_avatar_decorations
    @avatar_decorations = {}
    return unless Setting.avatar_decorations_enabled

    decoration_ids = @accounts.flat_map { |account| Array(account.avatar_decorations).filter_map { |config| config['id'] } }.uniq
    AvatarDecoration.find_many_cached(decoration_ids) if decoration_ids.any?
    @accounts.each { |account| @avatar_decorations[account.id] = AvatarDecoration.visible_configs_for(account) }
  end

  def preload_pinned_notes
    @pinned_notes = {}
    return if @account_ids.empty?

    pins = StatusPin.where(account_id: @account_ids).includes(:status).order(:account_id, created_at: :desc).to_a
    statuses_by_account = Hash.new { |hash, key| hash[key] = [] }
    pins.each do |pin|
      status = pin.status
      statuses_by_account[pin.account_id] << status if status&.visibility.in?(%w(public unlisted))
    end

    statuses = statuses_by_account.values.flatten
    return if statuses.empty?

    context = MisskeyCompat::SerializationContext.for(statuses, current_account: @viewer)
    statuses_by_account.each do |account_id, account_statuses|
      @pinned_notes[account_id] = [
        account_statuses.map { |status| MisskeyCompat::MiId.encode(status.id) },
        account_statuses.map { |status| MisskeyCompat::NoteSerializer.serialize(status, context: context) },
      ]
    end
  end

  def preload_pinned_pages
    @pinned_pages = {}
    return unless Setting.pages_enabled
    return if @account_ids.empty?

    pages = Page.where(account_id: @account_ids, is_main: true, visibility: 'public')
      .includes(:account, eye_catching_media_attachment: { drive_file: :custom_name })
      .to_a
    @pinned_pages_context = MisskeyCompat::PageCollectionContext.for(pages, current_account: @viewer)
    pages.each { |page| @pinned_pages[page.account_id] = page }
  end
end
