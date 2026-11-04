# frozen_string_literal: true

module Sharlayan::ChatMediaToken
  PURPOSE = :chat_media
  TTL = 10.minutes
  # Browsers cache a picture by its whole address, so the token stays the same for a moment instead of changing with
  # every response. It is dated from the start of the moment, so it never works for longer than TTL.
  STABLE_FOR = 1.minute

  module_function

  def generate(media, viewer, misskey: false)
    verifier.generate({ 'media_id' => media.id, 'account_id' => viewer.id, 'misskey' => misskey }, expires_at: stable_start + TTL, purpose: PURPOSE)
  end

  def stable_start
    Time.zone.at(Time.current.to_i / STABLE_FOR.to_i * STABLE_FOR.to_i)
  end

  # Only proves that this server signed it for this attachment, without asking the database who may see it.
  def signed_for?(token, media_id)
    token.is_a?(String) && verifier.verified(token, purpose: PURPOSE)&.dig('media_id').to_s == media_id.to_s
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError
    false
  end

  def viewer(token, media)
    payload = verifier.verified(token, purpose: PURPOSE)
    return if payload.nil? || payload['media_id'] != media.id
    return if payload['misskey'] && !Setting.misskey_compat_enabled

    account = Account.local.find_by(id: payload['account_id'])
    account if account&.user&.functional?
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError
    nil
  end

  def verifier
    Rails.application.message_verifier('chat_media')
  end
end
