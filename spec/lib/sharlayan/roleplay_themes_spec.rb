# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::RoleplayThemes do
  describe '.flavours' do
    it 'offers the installed glitch-based flavours' do
      expect(described_class.flavours).to contain_exactly('glitch', 'glitch-classic')
    end

    it 'omits a glitch-based flavour that is not installed' do
      allow(Themes.instance).to receive(:flavours).and_return(%w(glitch vanilla))

      expect(described_class.flavours).to eq(['glitch'])
    end
  end

  describe '.parse' do
    it 'reads a plain skin as a glitch skin' do
      expect(described_class.parse('default')).to eq(%w(glitch default))
    end

    it 'reads a skin of the legacy glitch flavour' do
      expect(described_class.parse('glitch-classic/birdsiteui')).to eq(%w(glitch-classic birdsiteui))
    end

    it 'rejects flavours outside roleplay mode support' do
      expect(described_class.parse('vanilla/default')).to be_nil
    end

    it 'rejects skins that the flavour does not provide' do
      expect(described_class.parse('glitch/missing')).to be_nil
      expect(described_class.parse('missing')).to be_nil
    end

    it 'treats blank values as no forced theme' do
      expect(described_class.parse('')).to be_nil
      expect(described_class.parse(nil)).to be_nil
    end
  end

  describe '.normalize' do
    it 'qualifies a plain skin with the glitch flavour' do
      expect(described_class.normalize('birdsiteui')).to eq('glitch/birdsiteui')
      expect(described_class.normalize('glitch-classic/default')).to eq('glitch-classic/default')
      expect(described_class.normalize('missing')).to be_nil
    end
  end

  describe '.flavour_for' do
    it 'keeps the first supported candidate and falls back to glitch' do
      expect(described_class.flavour_for('vanilla', 'glitch-classic')).to eq('glitch-classic')
      expect(described_class.flavour_for('vanilla', nil)).to eq('glitch')
    end
  end
end
