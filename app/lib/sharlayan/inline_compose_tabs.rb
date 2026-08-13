# frozen_string_literal: true

module Sharlayan::InlineComposeTabs
  ALLOWED_TYPES = %w(list antenna).freeze
  MAX_TABS = 100
  MAX_DATABASE_ID = (2**63) - 1

  module_function

  def normalize(value)
    invalid! unless value.is_a?(Array) && value.size <= MAX_TABS

    value.map do |tab|
      invalid! unless tab.respond_to?(:key?)

      type = (tab[:type] || tab['type']).to_s
      id = (tab[:id] || tab['id']).to_s
      valid_id = id.match?(/\A[1-9]\d{0,18}\z/) && id.to_i <= MAX_DATABASE_ID
      invalid! unless ALLOWED_TYPES.include?(type) && valid_id

      { 'type' => type, 'id' => id }
    end.uniq
  end

  def invalid!
    raise Mastodon::InvalidParameterError, "Invalid value for 'tabs'"
  end
end
