# frozen_string_literal: true

require 'rails_helper'
require 'request_store'

RSpec.describe InstanceMetadataSerializable do
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

  describe '#instance_metadata and #include_instance_metadata?' do
    it 'returns nil metadata and excludes it when the domain is blank' do
      expect(test_serializer_class.new(serializable_object, domain: nil).instance_metadata).to be_nil
      expect(test_serializer_class.new(serializable_object, domain: '').instance_metadata).to be_nil
      expect(test_serializer_class.new(serializable_object, domain: nil).include_instance_metadata?).to be false
    end

    context 'when domain is present' do
      let(:domain) { 'remote.example.com' }
      let(:other_domain) { 'other.example.com' }

      def instance_metadata_for(target_domain)
        test_serializer_class.new(serializable_object, domain: target_domain).instance_metadata
      end

      it 'includes the serialized metadata hash' do
        Fabricate(:instance_metadata, domain: domain, software: 'mastodon', theme_color: '#6364FF', instance_name: 'Test Instance', favicon_url: '/system/instance_favicons/test.ico')

        serializer = test_serializer_class.new(serializable_object, domain: domain)
        result = serializer.instance_metadata

        expect(serializer.include_instance_metadata?).to be true
        expect(result).to be_a(Hash)
        expect(result[:domain]).to eq(domain)
        expect(result[:software]).to eq('mastodon')
        expect(result[:theme_color]).to eq('#6364FF')
        expect(result[:instance_name]).to eq('Test Instance')
        expect(result[:favicon_url]).to eq('/system/instance_favicons/test.ico')
      end

      it 'creates metadata record if it does not exist' do
        instance_metadata_for(domain)

        expect(InstanceMetadata.exists?(domain: domain)).to be true
      end

      it 'schedules an update when metadata was never fetched or is outdated' do
        Fabricate(:instance_metadata, domain: domain, software: nil, metadata_updated_at: nil)
        Fabricate(:instance_metadata, domain: other_domain, software: 'mastodon', instance_name: 'Test', metadata_updated_at: 2.days.ago)

        instance_metadata_for(domain)
        instance_metadata_for(other_domain)

        expect(InstanceMetadataUpdateWorker).to have_received(:perform_async).with(domain)
        expect(InstanceMetadataUpdateWorker).to have_received(:perform_async).with(other_domain)
      end

      it 'does not schedule an update for fresh metadata, even when fields are missing' do
        Fabricate(:instance_metadata, domain: domain, software: nil, instance_name: nil, metadata_updated_at: 1.hour.ago)
        Fabricate(:instance_metadata, domain: other_domain, software: 'mastodon', instance_name: 'Test', metadata_updated_at: 1.hour.ago)

        instance_metadata_for(domain)
        instance_metadata_for(other_domain)

        expect(InstanceMetadataUpdateWorker).to_not have_received(:perform_async)
      end

      it 'uses fallback values in serialized output' do
        Fabricate(:instance_metadata, domain: domain, software: 'mastodon', theme_color: nil, instance_name: nil, favicon_url: nil)

        result = instance_metadata_for(domain)

        expect(result[:theme_color]).to eq('#6364FF')
        expect(result[:instance_name]).to eq(domain)
        expect(result[:favicon_url]).to eq("https://#{domain}/favicon.ico")
      end
    end
  end
end
