# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstanceMetadata do
  def build_metadata(**attributes)
    Fabricate.build(:instance_metadata, **attributes)
  end

  describe 'validations' do
    it 'requires domain to be present and unique' do
      Fabricate(:instance_metadata, domain: 'example.com')
      blank = described_class.new(domain: nil)
      taken = described_class.new(domain: 'example.com')

      expect(blank).to_not be_valid
      expect(blank.errors[:domain]).to include("can't be blank")
      expect(taken).to_not be_valid
      expect(taken.errors[:domain]).to include('has already been taken')
    end
  end

  describe '.for_domain' do
    it 'returns the existing record or creates a new one' do
      existing = Fabricate(:instance_metadata, domain: 'existing.example.com')
      expect(described_class.for_domain('existing.example.com')).to eq(existing)

      result = described_class.for_domain('new.example.com')
      expect(result).to be_persisted
      expect(result.domain).to eq('new.example.com')
    end
  end

  describe '.schedule_refresh' do
    before { allow(InstanceMetadataUpdateWorker).to receive(:perform_async) }

    it 'ignores blank domains and enqueues one refresh per domain until the request store is cleared' do
      described_class.schedule_refresh('')

      expect(InstanceMetadataUpdateWorker).to_not have_received(:perform_async)

      3.times { described_class.schedule_refresh('busy.example') }
      described_class.schedule_refresh('other.example')

      expect(InstanceMetadataUpdateWorker).to have_received(:perform_async).with('busy.example').once
      expect(InstanceMetadataUpdateWorker).to have_received(:perform_async).with('other.example').once

      RequestStore.clear!
      described_class.schedule_refresh('busy.example')

      expect(InstanceMetadataUpdateWorker).to have_received(:perform_async).with('busy.example').twice
    end
  end

  describe '#default_theme_color' do
    it 'returns the case-insensitive software color, falling back to the mastodon color' do
      expect(build_metadata(software: 'misskey').default_theme_color).to eq('#A1CA03')
      expect(build_metadata(software: 'Misskey').default_theme_color).to eq('#A1CA03')
      expect(build_metadata(software: 'unknown_software').default_theme_color).to eq('#6364FF')
      expect(build_metadata(software: nil).default_theme_color).to eq('#6364FF')
    end
  end

  describe '#theme_color_with_fallback' do
    it 'returns the stored theme_color or the software default when blank' do
      expect(build_metadata(theme_color: '#FF0000', software: 'mastodon').theme_color_with_fallback).to eq('#FF0000')
      expect(build_metadata(theme_color: nil, software: 'misskey').theme_color_with_fallback).to eq('#A1CA03')
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
    it 'is true when never updated or older than 7 days, and false when recent' do
      expect(build_metadata(theme_color_updated_at: nil).theme_color_needs_update?).to be true
      expect(build_metadata(theme_color_updated_at: 8.days.ago).theme_color_needs_update?).to be true
      expect(build_metadata(theme_color_updated_at: 1.day.ago).theme_color_needs_update?).to be false
    end
  end

  describe '#favicon_url_with_fallback' do
    it 'returns the stored favicon_url or the default favicon URL' do
      expect(build_metadata(domain: 'example.com', favicon_url: '/system/instance_favicons/example.com.ico').favicon_url_with_fallback).to eq('/system/instance_favicons/example.com.ico')
      expect(build_metadata(domain: 'example.com', favicon_url: nil).favicon_url_with_fallback).to eq('https://example.com/favicon.ico')
    end
  end

  describe '#instance_name_with_fallback' do
    it 'returns the stored instance_name or the domain' do
      expect(build_metadata(domain: 'example.com', instance_name: 'My Instance').instance_name_with_fallback).to eq('My Instance')
      expect(build_metadata(domain: 'example.com', instance_name: nil).instance_name_with_fallback).to eq('example.com')
    end
  end

  describe '#metadata_needs_update?' do
    it 'is true when never updated or older than 1 day, and false when recent' do
      expect(build_metadata(metadata_updated_at: nil).metadata_needs_update?).to be true
      expect(build_metadata(metadata_updated_at: 2.days.ago).metadata_needs_update?).to be true
      expect(build_metadata(metadata_updated_at: 1.hour.ago).metadata_needs_update?).to be false
    end
  end

  describe '#software_info_missing?' do
    it 'is true for nil or empty software and false when present' do
      expect(build_metadata(software: nil).software_info_missing?).to be true
      expect(build_metadata(software: '').software_info_missing?).to be true
      expect(build_metadata(software: 'mastodon').software_info_missing?).to be false
    end
  end

  describe '#needs_software_update?' do
    it 'is true only when software is missing and metadata is outdated' do
      expect(build_metadata(software: nil, metadata_updated_at: 2.days.ago).needs_software_update?).to be true
      expect(build_metadata(software: 'mastodon', metadata_updated_at: 2.days.ago).needs_software_update?).to be false
      expect(build_metadata(software: nil, metadata_updated_at: 1.hour.ago).needs_software_update?).to be false
    end
  end

  describe '#misskey_based?' do
    it 'is case-insensitively true for misskey and its variants and false otherwise' do
      expect(build_metadata(software: nil).misskey_based?).to be false
      expect(build_metadata(software: 'mastodon').misskey_based?).to be false
      expect(build_metadata(software: 'misskey').misskey_based?).to be true
      expect(build_metadata(software: 'Misskey').misskey_based?).to be true
      %w(sharkey firefish calckey foundkey magnetar iceshrimp catodon cherrypick).each do |variant|
        expect(build_metadata(software: variant).misskey_based?).to be(true), "Expected #{variant} to be misskey_based"
      end
    end
  end

  describe '#supports_feature?' do
    it 'reflects the features advertised in nodeinfo' do
      record = build_metadata(software: 'mastodon', features: %w(emoji_reaction circle))
      expect(record.supports_feature?('emoji_reaction')).to be true
      expect(record.supports_feature?(:circle)).to be true
      expect(build_metadata(software: 'mastodon', features: []).supports_feature?('emoji_reaction')).to be false
    end
  end

  describe '#server_features' do
    it 'enables emoji reactions and quotes for misskey variants, Hollo and Hackers Pub by software name alone' do
      %w(sharkey hollo hackerspub).each do |software|
        expect(build_metadata(software:, features: []).server_features).to include(emoji_reaction: true, quote: true)
      end
    end

    it 'enables capabilities advertised via nodeinfo features and keeps them disabled for a vanilla mastodon server' do
      expect(build_metadata(software: 'mastodon', features: %w(emoji_reaction circle status_reference)).server_features).to include(emoji_reaction: true, circle: true, status_reference: true)
      expect(build_metadata(software: 'mastodon', features: []).server_features).to include(emoji_reaction: false, quote: false, circle: false, status_reference: false)
    end
  end
end
