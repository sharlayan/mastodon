# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MfmDetector do
  describe '.contains_mfm?' do
    it 'returns true for text with MFM function syntax' do
      expect(described_class.contains_mfm?('$[tada hello]')).to be true
      expect(described_class.contains_mfm?('$[spin.speed=2s text]')).to be true
      expect(described_class.contains_mfm?('$[fg.color=f00 red text]')).to be true
    end

    it 'returns false for plain text' do
      expect(described_class.contains_mfm?('hello world')).to be false
      expect(described_class.contains_mfm?('just a $dollar sign')).to be false
    end

    it 'returns false for blank text' do
      expect(described_class.contains_mfm?(nil)).to be false
      expect(described_class.contains_mfm?('')).to be false
    end

    it 'returns false for partial MFM-like syntax' do
      expect(described_class.contains_mfm?('$[notclosed')).to be false
    end
  end

  describe '.extract_tags' do
    it 'extracts known MFM tags' do
      text = '$[tada hello] and $[spin.speed=1s world]'
      expect(described_class.extract_tags(text)).to contain_exactly('tada', 'spin')
    end

    it 'ignores unknown tags' do
      text = '$[unknown hello] and $[tada world]'
      expect(described_class.extract_tags(text)).to eq(['tada'])
    end

    it 'returns unique tags' do
      text = '$[tada a] $[tada b]'
      expect(described_class.extract_tags(text)).to eq(['tada'])
    end

    it 'returns empty array for blank text' do
      expect(described_class.extract_tags(nil)).to eq([])
      expect(described_class.extract_tags('')).to eq([])
    end
  end
end
