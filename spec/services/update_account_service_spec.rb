# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UpdateAccountService do
  subject { described_class.new }

  describe 'updating avatar decorations' do
    let(:account) { Fabricate(:user).account }

    before do
      Setting.avatar_decorations_enabled = true
    end

    context 'when local decorations are enabled' do
      before { Setting.avatar_decorations_local_only_view = false }

      it 'saves an available local decoration selection' do
        decoration = Fabricate(:avatar_decoration, approved: true)

        subject.call(account, { avatar_decorations: [{ id: decoration.id, scale: 1.2 }] })

        expect(account.reload.avatar_decorations).to contain_exactly(include('id' => decoration.id, 'scale' => 1.2))
      end
    end

    context 'when only remote decorations may be viewed' do
      before { Setting.avatar_decorations_local_only_view = true }

      it 'rejects local decoration selections' do
        decoration = Fabricate(:avatar_decoration, approved: true)

        subject.call(account, { avatar_decorations: [{ id: decoration.id }] })

        expect(account.reload.avatar_decorations).to be_empty
      end
    end
  end

  describe 'switching form locked to unlocked accounts', :inline_jobs do
    let(:account) { Fabricate(:account, locked: true) }
    let(:alice)   { Fabricate(:account) }
    let(:bob)     { Fabricate(:account) }
    let(:eve)     { Fabricate(:account) }

    before do
      bob.touch(:silenced_at)
      account.mute!(eve)

      FollowService.new.call(alice, account)
      FollowService.new.call(bob, account)
      FollowService.new.call(eve, account)
    end

    it 'auto accepts pending follow requests from appropriate accounts' do
      subject.call(account, { locked: false })

      expect(alice).to be_following(account)
      expect(alice).to_not be_requested(account)

      expect(bob).to_not be_following(account)
      expect(bob).to be_requested(account)

      expect(eve).to be_following(account)
      expect(eve).to_not be_requested(account)
    end
  end

  describe 'adding domains to attribution_domains' do
    let(:account) { Fabricate(:account) }
    let!(:preview_card) { Fabricate(:preview_card, url: 'https://writer.example.com/article', unverified_author_account: account, author_account: nil) }
    let!(:unattributable_preview_card) { Fabricate(:preview_card, url: 'https://otherwriter.example.com/article', unverified_author_account: account, author_account: nil) }
    let!(:unrelated_preview_card) { Fabricate(:preview_card) }

    it 'reattributes expected preview cards' do
      expect { subject.call(account, { attribution_domains: ['writer.example.com'] }) }
        .to change { preview_card.reload.author_account }.from(nil).to(account)
        .and not_change { unattributable_preview_card.reload.author_account }
        .and(not_change { unrelated_preview_card.reload.author_account })
    end
  end
end
