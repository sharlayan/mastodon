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

    it 'treats subdomains of a blocked domain as blocked' do
      Fabricate(:avatar_decoration_domain_block, domain: 'blocked.example')

      expect(described_class.blocked?('sub.blocked.example')).to be true
      expect(described_class.blocked?('notblocked.example')).to be false
    end
  end

  describe '.blocked_in?' do
    it 'matches subdomains against the cached domain set' do
      blocked = Set['blocked.example']

      expect(described_class.blocked_in?(blocked, 'a.b.blocked.example')).to be true
      expect(described_class.blocked_in?(blocked, 'example')).to be false
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
