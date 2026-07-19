# frozen_string_literal: true

module Sharlayan::Account::Mfm
  extend ActiveSupport::Concern

  included do
    before_save :recompute_mfm, if: :mfm_source_changed?
  end

  private

  def mfm_source_changed?
    will_save_change_to_note? || will_save_change_to_fields?
  end

  def recompute_mfm
    self.mfm = MfmDetector.contains_mfm?(note) ||
               fields.any? { |field| MfmDetector.contains_mfm?(field.value) }
  end
end
