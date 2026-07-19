# frozen_string_literal: true

module Sharlayan::ActivityPubNoteSerialization
  extend ActiveSupport::Concern

  prepended do
    context_extensions :limited_scope

    attribute :limited_scope, key: :limitedScope, if: :limited_scope?
    attribute :_misskey_content, if: :local_mfm?
    attribute :source, if: :local_mfm?
  end

  def content
    return super unless local_mfm?

    MfmHtmlConverter.convert_in_html(super)
  end

  def limited_scope
    ActivityPub::TagManager.instance.limited_scope(object)
  end

  def limited_scope?
    object.limited_visibility? && limited_scope.present?
  end

  def local_mfm?
    object.local? && object.mfm?
  end

  def _misskey_content
    object.text
  end

  def source
    {
      content: object.text,
      mediaType: 'text/x.misskeymarkdown',
    }
  end

  def to
    return super unless instance_options[:promote_to_public]

    ActivityPub::TagManager.instance.cc(object)
  end

  def cc
    return super unless instance_options[:promote_to_public]

    ActivityPub::TagManager.instance.to(object)
  end
end
