# frozen_string_literal: true

require 'rails_helper'

RSpec.describe I18n do
  subject(:locale_keys) do
    %w(en ko ja).to_h do |locale|
      data = YAML.safe_load_file(Rails.root.join("config/locales/sharlayan.#{locale}.yml"), aliases: true).fetch(locale)
      [locale, flatten_keys(data)]
    end
  end

  def flatten_keys(value, prefix = [])
    return [prefix.join('.')] unless value.is_a?(Hash)

    value.flat_map { |key, child| flatten_keys(child, prefix + [key]) }.sort
  end

  it 'uses the same key set for English, Korean, and Japanese' do
    expect(locale_keys.fetch('ko')).to eq(locale_keys.fetch('en'))
    expect(locale_keys.fetch('ja')).to eq(locale_keys.fetch('en'))
  end

  it 'includes shared translations referenced by Sharlayan views' do
    expect(locale_keys.values).to all(include('datetime.distance_in_words.ago', 'exports.json'))
  end
end
