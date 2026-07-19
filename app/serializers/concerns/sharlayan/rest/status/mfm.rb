# frozen_string_literal: true

module Sharlayan::REST::Status::Mfm
  extend ActiveSupport::Concern

  included do
    attribute :mfm
    attribute :mfm_text, if: :mfm_text?
  end

  def mfm_text?
    object.mfm? && object.mfm_text.present?
  end
end
