# frozen_string_literal: true

module Sharlayan::ActivityPubStatusParserExtensions
  extend ActiveSupport::Concern

  def text
    sanitize_misskey_quote_break(super)
  end

  def mfm?
    mfm_source_text.present? || MfmDetector.contains_mfm?(text)
  end

  def mfm_source_text
    source = @object['source']
    return source['content'].presence if source.is_a?(Hash) && source['mediaType']&.include?('misskeymarkdown')

    @object['_misskey_content'].presence
  end

  def limited_scope
    ActivityPub::TagManager.instance.limited_scope_from_uri(@object['limitedScope'])
  end

  def quote_policy
    return super unless from_misskey? && [:public, :unlisted].include?(visibility)

    InteractionPolicy::POLICY_FLAGS[:followers] << 16
  end

  def from_misskey?
    return false unless @json.is_a?(Hash)

    as_array(@json['@context']).any? { |context| context.is_a?(Hash) && context.key?('misskey') }
  end

  private

  def sanitize_misskey_quote_break(content)
    return content if content.blank? || !from_misskey?

    content.gsub(%r{<br\s*/>\s*(?=<span\s+class=["']quote-inline["']>)}, '')
  end
end
