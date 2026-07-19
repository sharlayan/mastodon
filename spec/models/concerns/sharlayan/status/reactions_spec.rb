# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::Status::Reactions do
  let(:status) { Fabricate(:status) }
  let(:viewer) { Fabricate(:account) }
  let(:remote_emoji) { Fabricate(:custom_emoji, shortcode: 'party', domain: 'remote.example') }
  let!(:local_counterpart) { Fabricate(:custom_emoji, shortcode: 'party', domain: nil) }

  before do
    Fabricate(:status_reaction, status: status, account: viewer, name: 'party', custom_emoji: remote_emoji)
  end

  describe '.reaction_groups_map' do
    it 'preloads custom emoji and local counterpart associations' do
      reaction = Status.reaction_groups_map([status.id], viewer.id).fetch(status.id).first

      expect(reaction.association(:custom_emoji)).to be_loaded
      expect(reaction.custom_emoji.association(:local_counterpart)).to be_loaded
      expect(reaction.custom_emoji.local_counterpart).to eq(local_counterpart)
      expect(reaction.me).to be true
    end

    it 'excludes reactions from blocked accounts' do
      blocked_account = Fabricate(:account)
      Fabricate(:status_reaction, status: status, account: blocked_account, name: '👍', custom_emoji: nil)
      viewer.block!(blocked_account)

      groups = Status.reaction_groups_map([status.id], viewer.id).fetch(status.id)

      expect(groups.map(&:name)).to contain_exactly('party')
    end
  end

  describe '#reactions' do
    it 'preloads custom emoji and local counterpart associations' do
      reaction = status.reactions(viewer.id).first

      expect(reaction.association(:custom_emoji)).to be_loaded
      expect(reaction.custom_emoji.association(:local_counterpart)).to be_loaded
    end
  end
end
