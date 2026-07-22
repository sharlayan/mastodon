# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstanceMetadata do
  describe 'validations' do
    it 'requires domain to be present' do
      record = described_class.new(domain: nil)
      expect(record).to_not be_valid
      expect(record.errors[:domain]).to include("can't be blank")
    end

    it 'requires domain to be unique' do
      Fabricate(:instance_metadata, domain: 'example.com')
      record = described_class.new(domain: 'example.com')
      expect(record).to_not be_valid
      expect(record.errors[:domain]).to include('has already been taken')
    end
  end

  describe '.for_domain' do
    it 'returns existing record when found' do
      existing = Fabricate(:instance_metadata, domain: 'existing.example.com')
      expect(described_class.for_domain('existing.example.com')).to eq(existing)
    end

    it 'creates a new record when not found' do
      result = described_class.for_domain('new.example.com')
      expect(result).to be_persisted
      expect(result.domain).to eq('new.example.com')
    end
  end

  describe '#default_theme_color' do
    it 'returns the correct color for known software' do
      record = Fabricate(:instance_metadata, software: 'misskey')
      expect(record.default_theme_color).to eq('#A1CA03')
    end

    it 'returns mastodon color for unknown software' do
      record = Fabricate(:instance_metadata, software: 'unknown_software')
      expect(record.default_theme_color).to eq('#6364FF')
    end

    it 'returns mastodon color when software is nil' do
      record = Fabricate(:instance_metadata, software: nil)
      expect(record.default_theme_color).to eq('#6364FF')
    end

    it 'is case-insensitive for software matching' do
      record = Fabricate(:instance_metadata, software: 'Misskey')
      expect(record.default_theme_color).to eq('#A1CA03')
    end
  end

  describe '#theme_color_with_fallback' do
    it 'returns stored theme_color when present' do
      record = Fabricate(:instance_metadata, theme_color: '#FF0000', software: 'mastodon')
      expect(record.theme_color_with_fallback).to eq('#FF0000')
    end

    it 'returns default theme color when theme_color is blank' do
      record = Fabricate(:instance_metadata, theme_color: nil, software: 'misskey')
      expect(record.theme_color_with_fallback).to eq('#A1CA03')
    end

    it 'uses built-in colors for additional Fediverse software families' do
      expect(described_class.new(domain: 'misskey.example', software: 'iceshrimp').theme_color_with_fallback).to eq('#A1CA03')
      expect(described_class.new(domain: 'mastodon.example', software: 'kmyblue').theme_color_with_fallback).to eq('#6364FF')
      expect(described_class.new(domain: 'video.example', software: 'owncast').theme_color_with_fallback).to eq('#7871FF')
      expect(described_class.new(domain: 'blog.example', software: 'hollo').theme_color_with_fallback).to eq('#000000')
      expect(described_class.new(domain: 'framework.example', software: 'fedify').theme_color_with_fallback).to eq('#0284C7')
      expect(described_class.new(domain: 'hackers.example', software: 'hackerspub').theme_color_with_fallback).to eq('#000000')
    end
  end

  describe '#theme_color_needs_update?' do
    it 'returns true when theme_color_updated_at is nil' do
      record = Fabricate(:instance_metadata, theme_color_updated_at: nil)
      expect(record.theme_color_needs_update?).to be true
    end

    it 'returns true when older than 7 days' do
      record = Fabricate(:instance_metadata, theme_color_updated_at: 8.days.ago)
      expect(record.theme_color_needs_update?).to be true
    end

    it 'returns false when recent' do
      record = Fabricate(:instance_metadata, theme_color_updated_at: 1.day.ago)
      expect(record.theme_color_needs_update?).to be false
    end
  end

  describe '#favicon_url_with_fallback' do
    it 'returns stored favicon_url when present' do
      record = Fabricate(:instance_metadata, domain: 'example.com', favicon_url: '/system/instance_favicons/example.com.ico')
      expect(record.favicon_url_with_fallback).to eq('/system/instance_favicons/example.com.ico')
    end

    it 'falls back to default favicon URL' do
      record = Fabricate(:instance_metadata, domain: 'example.com', favicon_url: nil)
      expect(record.favicon_url_with_fallback).to eq('https://example.com/favicon.ico')
    end
  end

  describe '#instance_name_with_fallback' do
    it 'returns stored instance_name when present' do
      record = Fabricate(:instance_metadata, domain: 'example.com', instance_name: 'My Instance')
      expect(record.instance_name_with_fallback).to eq('My Instance')
    end

    it 'falls back to domain' do
      record = Fabricate(:instance_metadata, domain: 'example.com', instance_name: nil)
      expect(record.instance_name_with_fallback).to eq('example.com')
    end
  end

  describe '#metadata_needs_update?' do
    it 'returns true when metadata_updated_at is nil' do
      record = Fabricate(:instance_metadata, metadata_updated_at: nil)
      expect(record.metadata_needs_update?).to be true
    end

    it 'returns true when older than 1 day' do
      record = Fabricate(:instance_metadata, metadata_updated_at: 2.days.ago)
      expect(record.metadata_needs_update?).to be true
    end

    it 'returns false when recent' do
      record = Fabricate(:instance_metadata, metadata_updated_at: 1.hour.ago)
      expect(record.metadata_needs_update?).to be false
    end
  end

  describe '#software_info_missing?' do
    it 'returns true when software is blank' do
      record = Fabricate(:instance_metadata, software: nil)
      expect(record.software_info_missing?).to be true
    end

    it 'returns true when software is empty string' do
      record = Fabricate(:instance_metadata, software: '')
      expect(record.software_info_missing?).to be true
    end

    it 'returns false when software is present' do
      record = Fabricate(:instance_metadata, software: 'mastodon')
      expect(record.software_info_missing?).to be false
    end
  end

  describe '#needs_software_update?' do
    it 'returns true when software is missing and metadata is outdated' do
      record = Fabricate(:instance_metadata, software: nil, metadata_updated_at: 2.days.ago)
      expect(record.needs_software_update?).to be true
    end

    it 'returns false when software is present' do
      record = Fabricate(:instance_metadata, software: 'mastodon', metadata_updated_at: 2.days.ago)
      expect(record.needs_software_update?).to be false
    end

    it 'returns false when metadata is recent even if software missing' do
      record = Fabricate(:instance_metadata, software: nil, metadata_updated_at: 1.hour.ago)
      expect(record.needs_software_update?).to be false
    end
  end

  describe '#misskey_based?' do
    it 'returns false when software is blank' do
      record = Fabricate(:instance_metadata, software: nil)
      expect(record.misskey_based?).to be false
    end

    it 'returns true for misskey' do
      record = Fabricate(:instance_metadata, software: 'misskey')
      expect(record.misskey_based?).to be true
    end

    it 'returns true for misskey variants' do
      %w(sharkey firefish calckey foundkey magnetar iceshrimp catodon cherrypick).each do |variant|
        record = Fabricate(:instance_metadata, software: variant)
        expect(record.misskey_based?).to be(true), "Expected #{variant} to be misskey_based"
      end
    end

    it 'returns false for non-misskey software' do
      record = Fabricate(:instance_metadata, software: 'mastodon')
      expect(record.misskey_based?).to be false
    end

    it 'is case-insensitive' do
      record = Fabricate(:instance_metadata, software: 'Misskey')
      expect(record.misskey_based?).to be true
    end
  end

  describe '#supports_feature?' do
    it 'returns true when the feature is advertised in nodeinfo' do
      record = Fabricate(:instance_metadata, software: 'mastodon', features: %w(emoji_reaction circle))
      expect(record.supports_feature?('emoji_reaction')).to be true
      expect(record.supports_feature?(:circle)).to be true
    end

    it 'returns false when the feature is not advertised' do
      record = Fabricate(:instance_metadata, software: 'mastodon', features: [])
      expect(record.supports_feature?('emoji_reaction')).to be false
    end
  end

  describe '#server_features' do
    it 'enables emoji reactions and quotes for misskey variants by software name alone' do
      record = Fabricate(:instance_metadata, software: 'sharkey', features: [])
      expect(record.server_features).to include(emoji_reaction: true, quote: true)
    end

    it 'enables emoji reactions and quotes for Hollo and Hackers Pub by software name alone' do
      %w(hollo hackerspub).each do |software|
        record = Fabricate(:instance_metadata, software:, features: [])
        expect(record.server_features).to include(emoji_reaction: true, quote: true)
      end
    end

    it 'enables capabilities advertised via nodeinfo features for mastodon-family servers' do
      record = Fabricate(:instance_metadata, software: 'mastodon', features: %w(emoji_reaction circle status_reference))
      expect(record.server_features).to include(emoji_reaction: true, circle: true, status_reference: true)
    end

    it 'keeps capabilities disabled for a vanilla mastodon server' do
      record = Fabricate(:instance_metadata, software: 'mastodon', features: [])
      expect(record.server_features).to include(emoji_reaction: false, quote: false, circle: false, status_reference: false)
    end
  end
end
