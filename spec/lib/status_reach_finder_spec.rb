# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StatusReachFinder do
  describe '#inboxes' do
    context 'with a local status' do
      subject { described_class.new(status) }

      let(:parent_status) { nil }
      let(:visibility) { :public }
      let(:alice) { Fabricate(:account, username: 'alice') }
      let(:status) { Fabricate(:status, account: alice, thread: parent_status, visibility: visibility) }

      context 'when it contains mentions of remote accounts' do
        let(:bob) { Fabricate(:account, username: 'bob', domain: 'foo.bar', protocol: :activitypub, inbox_url: 'https://foo.bar/inbox') }

        before do
          status.mentions.create!(account: bob, silent: false)
        end

        it 'includes the inbox of the mentioned account' do
          expect(subject.inboxes).to include 'https://foo.bar/inbox'
        end

        context 'when the status is private' do
          let(:visibility) { :private }
          let(:bob) do
            Fabricate(
              :account,
              username: 'bob',
              domain: 'foo.bar',
              protocol: :activitypub,
              inbox_url: 'https://foo.bar/users/bob/inbox',
              shared_inbox_url: 'https://foo.bar/inbox'
            )
          end

          it 'delivers the mention to the account inbox instead of the shared inbox' do
            expect(subject.inboxes)
              .to include('https://foo.bar/users/bob/inbox')
              .and not_include('https://foo.bar/inbox')
          end
        end
      end

      context 'when the status is private' do
        let(:visibility) { :private }
        let(:bob) do
          Fabricate(
            :account,
            username: 'bob',
            domain: 'foo.bar',
            protocol: :activitypub,
            inbox_url: 'https://foo.bar/users/bob/inbox',
            shared_inbox_url: 'https://foo.bar/inbox'
          )
        end
        let(:carol) do
          Fabricate(
            :account,
            username: 'carol',
            domain: 'foo.bar',
            protocol: :activitypub,
            inbox_url: 'https://foo.bar/users/carol/inbox',
            shared_inbox_url: 'https://foo.bar/inbox'
          )
        end

        before do
          Fabricate(:follow, account: bob, target_account: alice)
          Fabricate(:follow, account: carol, target_account: alice)
          status.mentions.create!(account: bob, silent: false)
        end

        it 'delivers to each follower inbox without using their shared inbox' do
          expect(subject.inboxes)
            .to include('https://foo.bar/users/bob/inbox', 'https://foo.bar/users/carol/inbox')
            .and not_include('https://foo.bar/inbox')
        end
      end

      context 'when it has been reblogged by a remote account' do
        let(:bob) { Fabricate(:account, username: 'bob', domain: 'foo.bar', protocol: :activitypub, inbox_url: 'https://foo.bar/inbox') }

        before do
          bob.statuses.create!(reblog: status)
        end

        it 'includes the inbox of the reblogger' do
          expect(subject.inboxes).to include 'https://foo.bar/inbox'
        end

        context 'when status is not public' do
          let(:visibility) { :private }

          it 'does not include the inbox of the reblogger' do
            expect(subject.inboxes).to_not include 'https://foo.bar/inbox'
          end
        end
      end

      context 'when it has been favourited by a remote account' do
        let(:bob) { Fabricate(:account, username: 'bob', domain: 'foo.bar', protocol: :activitypub, inbox_url: 'https://foo.bar/inbox') }

        before do
          bob.favourites.create!(status: status)
        end

        it 'includes the inbox of the favouriter' do
          expect(subject.inboxes).to include 'https://foo.bar/inbox'
        end

        context 'when status is not public' do
          let(:visibility) { :private }

          it 'does not include the inbox of the favouriter' do
            expect(subject.inboxes).to_not include 'https://foo.bar/inbox'
          end
        end
      end

      context 'when it has been replied to by a remote account' do
        let(:bob) { Fabricate(:account, username: 'bob', domain: 'foo.bar', protocol: :activitypub, inbox_url: 'https://foo.bar/inbox') }

        before do
          bob.statuses.create!(thread: status, text: 'Hoge')
        end

        it 'includes the inbox of the replier' do
          expect(subject.inboxes).to include 'https://foo.bar/inbox'
        end

        context 'when status is not public' do
          let(:visibility) { :private }

          it 'does not include the inbox of the replier' do
            expect(subject.inboxes).to_not include 'https://foo.bar/inbox'
          end
        end
      end

      context 'when it is a reply to a remote account' do
        let(:bob) { Fabricate(:account, username: 'bob', domain: 'foo.bar', protocol: :activitypub, inbox_url: 'https://foo.bar/inbox') }
        let(:parent_status) { Fabricate(:status, account: bob) }

        it 'includes the inbox of the replied-to account' do
          expect(subject.inboxes).to include 'https://foo.bar/inbox'
        end

        context 'when status is not public and replied-to account is not mentioned' do
          let(:visibility) { :private }

          it 'does not include the inbox of the replied-to account' do
            expect(subject.inboxes).to_not include 'https://foo.bar/inbox'
          end
        end
      end
    end
  end
end
