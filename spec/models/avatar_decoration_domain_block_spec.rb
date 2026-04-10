# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AvatarDecorationDomainBlock do
  describe 'validations' do
    it 'requires a domain' do
      block = described_class.new(domain: '')
      expect(block).to_not be_valid
    end

    it 'enforces domain uniqueness' do
      Fabricate(:avatar_decoration_domain_block, domain: 'example.com')
      dup = described_class.new(domain: 'example.com')
      expect(dup).to_not be_valid
    end
  end

  describe '.blocked?' do
    it 'returns true when domain is blocked' do
      Fabricate(:avatar_decoration_domain_block, domain: 'blocked.example')
      expect(described_class.blocked?('blocked.example')).to be true
    end

    it 'returns false when domain is not blocked' do
      expect(described_class.blocked?('safe.example')).to be false
    end
  end

  describe 'scopes' do
    describe '.by_domain' do
      it 'filters by domain' do
        block = Fabricate(:avatar_decoration_domain_block, domain: 'target.example')
        Fabricate(:avatar_decoration_domain_block, domain: 'other.example')
        expect(described_class.by_domain('target.example')).to contain_exactly(block)
      end
    end
  end
end
