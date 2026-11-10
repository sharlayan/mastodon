# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AvatarDecorationDomainBlock do
  describe 'validations' do
    it 'requires a unique domain' do
      Fabricate(:avatar_decoration_domain_block, domain: 'example.com')

      expect(described_class.new(domain: '')).to_not be_valid
      expect(described_class.new(domain: 'example.com')).to_not be_valid
    end
  end

  describe '.blocked? and .by_domain' do
    it 'treats a blocked domain and its subdomains as blocked and filters blocks by domain' do
      block = Fabricate(:avatar_decoration_domain_block, domain: 'blocked.example')
      Fabricate(:avatar_decoration_domain_block, domain: 'other.example')

      expect(described_class.blocked?('blocked.example')).to be true
      expect(described_class.blocked?('sub.blocked.example')).to be true
      expect(described_class.blocked?('safe.example')).to be false
      expect(described_class.blocked?('notblocked.example')).to be false
      expect(described_class.by_domain('blocked.example')).to contain_exactly(block)
    end
  end

  describe '.blocked_in?' do
    it 'matches subdomains against the cached domain set' do
      blocked = Set['blocked.example']

      expect(described_class.blocked_in?(blocked, 'a.b.blocked.example')).to be true
      expect(described_class.blocked_in?(blocked, 'example')).to be false
    end
  end
end
