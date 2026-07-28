# frozen_string_literal: true

module CustomEmojiResponseFilteringConcern
  extend ActiveSupport::Concern

  included do
    after_action :filter_custom_emojis_for_external_client
  end

  private

  def filter_custom_emojis_for_external_client
    return unless external_api_client?
    return unless current_account
    return unless response.media_type == 'application/json'
    return if response.body.blank?

    payload = JSON.parse(response.body)
    rules = CustomEmojiMuteCache.read(current_account.id)
    return if rules.empty?

    response.body = JSON.generate(CustomEmojiResponseFilter.filter(payload, rules))
  rescue JSON::ParserError
    nil
  end

  def external_api_client?
    token = respond_to?(:current_token, true) ? current_token : doorkeeper_token
    token.present? && !token.application&.superapp?
  end
end
