# frozen_string_literal: true

module MisskeyCompat::ChatMediaToken
  PURPOSE = :misskey_chat_media
  TTL = 10.minutes

  module_function

  def generate(media, viewer)
    verifier.generate({ 'media_id' => media.id, 'account_id' => viewer.id }, expires_in: TTL, purpose: PURPOSE)
  end

  def viewer(token, media)
    payload = verifier.verified(token, purpose: PURPOSE)
    return if payload.nil? || payload['media_id'] != media.id

    account = Account.local.find_by(id: payload['account_id'])
    account if account&.user&.functional?
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError
    nil
  end

  def verifier
    Rails.application.message_verifier('misskey_chat_media')
  end
end
