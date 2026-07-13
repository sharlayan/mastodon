# frozen_string_literal: true

require 'rails_helper'
require 'request_store'

RSpec.describe InstanceMetadataSerializable do
  # Create a test serializer that includes the concern
  let(:test_serializer_class) do
    Class.new(ActiveModel::Serializer) do
      include InstanceMetadataSerializable

      attribute :id

      def initialize(object, options = {})
        @test_domain = options[:domain]
        super
      end

      private

      def metadata_domain
        @test_domain
      end
    end
  end

  let(:serializable_object) { Struct.new(:id, :read_attribute_for_serialization).new(1, ->(_) { 1 }) }

  before do
    RequestStore.clear!
    allow(InstanceMetadataUpdateWorker).to receive(:perform_async)
  end

  describe '#instance_metadata' do
    context 'when domain is blank' do
      it 'returns nil' do
        serializer = test_serializer_class.new(serializable_object, domain: nil)
        expect(serializer.instance_metadata).to be_nil
      end

      it 'returns nil for empty string domain' do
        serializer = test_serializer_class.new(serializable_object, domain: '')
        expect(serializer.instance_metadata).to be_nil
      end
    end

    context 'when domain is present' do
      let(:domain) { 'remote.example.com' }

      it 'returns serialized metadata hash' do
        Fabricate(:instance_metadata, domain: domain, software: 'mastodon', theme_color: '#6364FF', instance_name: 'Test Instance', favicon_url: '/system/instance_favicons/test.ico')

        serializer = test_serializer_class.new(serializable_object, domain: domain)
        result = serializer.instance_metadata

        expect(result).to be_a(Hash)
        expect(result[:domain]).to eq(domain)
        expect(result[:software]).to eq('mastodon')
        expect(result[:theme_color]).to eq('#6364FF')
        expect(result[:instance_name]).to eq('Test Instance')
        expect(result[:favicon_url]).to eq('/system/instance_favicons/test.ico')
      end

      it 'creates metadata record if it does not exist' do
        serializer = test_serializer_class.new(serializable_object, domain: domain)
        serializer.instance_metadata

        expect(InstanceMetadata.exists?(domain: domain)).to be true
      end

      it 'schedules update when never fetched' do
        Fabricate(:instance_metadata, domain: domain, software: nil, metadata_updated_at: nil)

        serializer = test_serializer_class.new(serializable_object, domain: domain)
        serializer.instance_metadata

        expect(InstanceMetadataUpdateWorker).to have_received(:perform_async).with(domain)
      end

      it 'does not re-schedule fresh metadata even when fields are missing' do
        Fabricate(:instance_metadata, domain: domain, software: nil, instance_name: nil, metadata_updated_at: 1.hour.ago)

        serializer = test_serializer_class.new(serializable_object, domain: domain)
        serializer.instance_metadata

        expect(InstanceMetadataUpdateWorker).to_not have_received(:perform_async)
      end

      it 'schedules update when metadata is outdated' do
        Fabricate(:instance_metadata, domain: domain, software: 'mastodon', instance_name: 'Test', metadata_updated_at: 2.days.ago)

        serializer = test_serializer_class.new(serializable_object, domain: domain)
        serializer.instance_metadata

        expect(InstanceMetadataUpdateWorker).to have_received(:perform_async).with(domain)
      end

      it 'does not schedule update when metadata is fresh' do
        Fabricate(:instance_metadata, domain: domain, software: 'mastodon', instance_name: 'Test', metadata_updated_at: 1.hour.ago)

        serializer = test_serializer_class.new(serializable_object, domain: domain)
        serializer.instance_metadata

        expect(InstanceMetadataUpdateWorker).to_not have_received(:perform_async)
      end

      it 'uses fallback values in serialized output' do
        Fabricate(:instance_metadata, domain: domain, software: 'mastodon', theme_color: nil, instance_name: nil, favicon_url: nil)

        serializer = test_serializer_class.new(serializable_object, domain: domain)
        result = serializer.instance_metadata

        expect(result[:theme_color]).to eq('#6364FF') # mastodon default
        expect(result[:instance_name]).to eq(domain)
        expect(result[:favicon_url]).to eq("https://#{domain}/favicon.ico")
      end
    end
  end

  describe '#include_instance_metadata?' do
    it 'returns true when domain is present' do
      serializer = test_serializer_class.new(serializable_object, domain: 'example.com')
      expect(serializer.include_instance_metadata?).to be true
    end

    it 'returns false when domain is blank' do
      serializer = test_serializer_class.new(serializable_object, domain: nil)
      expect(serializer.include_instance_metadata?).to be false
    end
  end
end
