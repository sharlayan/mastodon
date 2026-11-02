# frozen_string_literal: true

class Export
  attr_reader :account

  def initialize(account)
    @account = account
  end

  def to_bookmarks_csv
    CSV.generate do |csv|
      account.bookmarks.includes(:status).reorder(id: :desc).each do |bookmark|
        csv << [ActivityPub::TagManager.instance.uri_for(bookmark.status)] if bookmark.status.present?
      end
    end
  end

  def to_blocked_accounts_csv
    to_csv account.blocking.select(:username, :domain)
  end

  def to_muted_accounts_csv
    CSV.generate(headers: ['Account address', 'Hide notifications'], write_headers: true) do |csv|
      account.mute_relationships.includes(:target_account).reorder(id: :desc).each do |mute|
        csv << [acct(mute.target_account), mute.hide_notifications]
      end
    end
  end

  def to_following_accounts_csv
    CSV.generate(headers: ['Account address', 'Show boosts', 'Notify on new posts', 'Languages'], write_headers: true) do |csv|
      account.active_relationships.includes(:target_account).reorder(id: :desc).each do |follow|
        csv << [acct(follow.target_account), follow.show_reblogs, follow.notify, follow.languages&.join(', ')]
      end
    end
  end

  def to_lists_csv
    CSV.generate do |csv|
      account.owned_lists.select(:title, :id).each do |list|
        list.accounts.select(:username, :domain).each do |account|
          csv << [list.title, acct(account)]
        end
      end
    end
  end

  def to_blocked_domains_csv
    CSV.generate do |csv|
      account.domain_blocks.pluck(:domain).each do |domain|
        csv << [domain]
      end
    end
  end

  def to_custom_filters_json
    data_collection = { custom_filters: [] }
    account.custom_filters.includes(:keywords, :statuses).order(:phrase).each do |filter|
      keywords_attributes = filter.keywords.map { |k| { keyword: k.keyword, whole_word: k.whole_word } }

      data_collection[:custom_filters] << {
        title: filter.title,
        expires_at: filter.expires_at,
        context: filter.context,
        action: filter.action,
        keywords_attributes: keywords_attributes,
        statuses: filter.statuses.map { |s| ActivityPub::TagManager.instance.uri_for(s.status) },
      }
    end
    JSON.generate(data_collection)
  end

  def to_clips_json
    data_collection = { clips: [] }
    account.clips.reorder(id: :desc).each do |clip|
      data_collection[:clips] << {
        title: clip.title,
        description: clip.description,
        public: clip.public,
        statuses: clip.statuses.reorder('clip_statuses.id DESC').limit(Clip::STATUSES_LIMIT).map { |status| ActivityPub::TagManager.instance.uri_for(status) },
      }
    end
    JSON.generate(data_collection)
  end

  def to_chat_json
    conversations = ChatConversation.for_account(account).includes(:accounts)
    messages = ChatMessage.visible_to(account)
      .where(chat_conversation_id: conversations.select(:id))
      .includes(:account, :media_attachments, reactions: :account)
      .order(id: :asc)
      .group_by(&:chat_conversation_id)

    JSON.generate(
      chat_conversations: conversations.map do |conversation|
        chat_conversation_data(conversation, messages.fetch(conversation.id, []))
      end
    )
  end

  private

  def chat_conversation_data(conversation, messages)
    {
      id: conversation.id.to_s,
      type: conversation.conversation_type,
      title: conversation.title,
      description: conversation.description,
      archived_at: conversation.archived_at,
      participants: conversation.accounts.map { |participant| acct(participant) },
      messages: messages.map { |message| chat_message_data(message) },
    }
  end

  def chat_message_data(message)
    {
      id: message.id.to_s,
      sender: acct(message.account),
      text: message.deleted? ? nil : message.text,
      reply_to_id: message.reply_to_id&.to_s,
      created_at: message.created_at,
      edited_at: message.edited_at,
      deleted_at: message.deleted_at,
      attachments: message.media_attachments.map { |attachment| chat_attachment_url(attachment) },
      reactions: message.reactions.map { |reaction| { reaction: reaction.reaction, account: acct(reaction.account) } },
    }
  end

  def chat_attachment_url(attachment)
    Rails.application.routes.url_helpers.media_proxy_url(attachment.id, :original, **ActionMailer::Base.default_url_options)
  end

  def to_csv(accounts)
    CSV.generate do |csv|
      accounts.each do |account|
        csv << [acct(account)]
      end
    end
  end

  def acct(account)
    account.local? ? account.local_username_and_domain : account.acct
  end
end
