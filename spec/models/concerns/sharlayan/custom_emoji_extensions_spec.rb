# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CustomEmoji, :attachment_processing do
  describe 'metadata validation' do
    subject(:custom_emoji) { Fabricate.build(:custom_emoji) }

    it 'rejects too many aliases and aliases and licenses over their length limits' do
      too_many = Fabricate.build(:custom_emoji, aliases: Array.new(CustomEmoji::ALIASES_MAX_COUNT + 1, 'alias'))

      expect(too_many).to_not be_valid
      expect(too_many.errors.of_kind?(:aliases, :too_many)).to be true

      custom_emoji.aliases = ['a' * (CustomEmoji::ALIAS_MAX_LENGTH + 1)]
      custom_emoji.license = 'a' * (CustomEmoji::LICENSE_MAX_LENGTH + 1)

      expect(custom_emoji).to_not be_valid
      expect(custom_emoji.errors.of_kind?(:aliases, :too_long)).to be true
      expect(custom_emoji.errors.of_kind?(:license, :too_long)).to be true
    end
  end

  describe '.search' do
    it 'matches aliases without losing shortcode matches' do
      alias_match = Fabricate(:custom_emoji, shortcode: 'blobcat', aliases: ['fluffy'])
      shortcode_match = Fabricate(:custom_emoji, shortcode: 'fluffydog', aliases: [])

      expect(described_class.search('fluffy')).to contain_exactly(alias_match, shortcode_match)
    end
  end
end
