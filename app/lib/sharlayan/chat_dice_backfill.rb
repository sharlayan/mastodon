# frozen_string_literal: true

class Sharlayan::ChatDiceBackfill
  include JsonLdHelper

  COMMAND_SQL_PATTERN = '^[[:space:]]*/dice([[:space:]]|$)'

  def call
    candidates.find_each.count { |message| backfill(message) }
  end

  def candidates
    ChatMessage.where(dice: nil, deleted_at: nil)
      .where.not(uri: nil)
      .where('chat_messages.text ~ ?', COMMAND_SQL_PATTERN)
      .joins(:account)
      .merge(Account.remote)
  end

  def backfill(message)
    notation = Sharlayan::ChatDice.notation(message.text)
    signer = signer_for(message)
    return false if notation.nil? || signer.nil?

    json = fetch_resource(message.uri, on_behalf_of: signer)
    return false unless json.is_a?(Hash) && json['type'] == 'Note' && value_or_id(json['attributedTo']) == message.account.uri

    dice = Sharlayan::ChatDice.parse(json['_misskey_dice'])
    return false unless dice && dice['notation'] == notation

    message.update_column(:dice, dice)
    true
  rescue *Mastodon::HTTP_CONNECTION_ERRORS, Mastodon::Error, Addressable::URI::InvalidURIError
    false
  end

  private

  def signer_for(message)
    message.chat_conversation.memberships
      .joins(:account)
      .merge(Account.local.without_suspended)
      .first&.account
  end
end
