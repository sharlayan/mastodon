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

    it 'excludes muted accounts from groups, counts, users, and account ids' do
      visible_account = Fabricate(:account)
      muted_account = Fabricate(:account)
      other_muted_account = Fabricate(:account)
      Fabricate(:status_reaction, status: status, account: visible_account, name: '👍', custom_emoji: nil)
      Fabricate(:status_reaction, status: status, account: muted_account, name: '👍', custom_emoji: nil)
      Fabricate(:status_reaction, status: status, account: other_muted_account, name: '👎', custom_emoji: nil)
      viewer.mute!(muted_account)
      viewer.mute!(other_muted_account)

      groups = Status.reaction_groups_map([status.id], viewer.id).fetch(status.id)
      reaction = groups.find { |group| group.name == '👍' }

      expect(groups.map(&:name)).to contain_exactly('party', '👍')
      expect(reaction.count).to eq(1)
      expect(reaction.users).to contain_exactly(visible_account)
      expect(reaction.account_ids).to contain_exactly(visible_account.id.to_s)
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
