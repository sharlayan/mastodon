# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BroadcastStatusUpdateWorker do
  subject { described_class.new }

  let(:account)  { Fabricate(:account) }
  let(:follower) { Fabricate(:account) }
  let(:status)   { Fabricate(:status, account: account) }
  let(:published_messages) { [] }

  before do
    follower.user # ensure user is created
    follower.follow!(account)
    allow(redis).to receive(:publish) do |channel, message|
      published_messages << [channel, JSON.parse(message)]
    end
  end

  describe '#perform' do
    context 'with a recent public status' do
      before do
        status.update(visibility: :public)
      end

      it 'publishes a status.reaction event to the status-specific channel' do
        subject.perform(status.id)

        expect(redis).to have_received(:publish).with("timeline:status:#{status.id}", a_string_including('"event":"status.reaction"'))
      end

      it 'only includes reaction update data in the payload' do
        reactor = Fabricate(:account)
        Fabricate(:status_reaction, status: status, account: reactor, name: '👍')

        subject.perform(status.id)

        message = published_messages.find { |channel, _message| channel == "timeline:status:#{status.id}" }.last
        expect(message['payload']).to match(
          'id' => status.id.to_s,
          'reactions_count' => 1,
          'reactions' => [include('name' => '👍', 'count' => 1, 'users' => [include('id' => reactor.id.to_s)])]
        )
        expect(message['payload'].keys).to contain_exactly('id', 'reactions_count', 'reactions')
      end

      it 'sends only the fields the client renders for each reaction user' do
        reactor = Fabricate(:account)
        Fabricate(:status_reaction, status: status, account: reactor, name: '👍')

        subject.perform(status.id)

        message = published_messages.find { |channel, _message| channel == "timeline:status:#{status.id}" }.last
        reaction = message['payload']['reactions'].first

        expect(reaction['users'].first.keys).to contain_exactly(
          'id', 'username', 'acct', 'display_name', 'avatar', 'avatar_static', 'is_cat', 'emojis'
        )
        expect(reaction).to_not have_key('local_counterpart')
      end

      it 'keeps the full account payload on the REST serializer' do
        reactor = Fabricate(:account)
        Fabricate(:status_reaction, status: status, account: reactor, name: '👍')

        rest = ActiveModelSerializers::SerializableResource.new(
          status.reactions, each_serializer: REST::ReactionSerializer
        ).as_json.first

        expect(rest[:users].first.keys).to include(:note, :fields, :followers_count, :url)
      end

      it 'publishes to the public timeline' do
        subject.perform(status.id)

        expect(redis).to have_received(:publish).with('timeline:public', anything)
      end

      it 'publishes to the author timeline' do
        subject.perform(status.id)

        expect(redis).to have_received(:publish).with("timeline:#{account.id}", anything)
      end

      it 'publishes to followers' do
        subject.perform(status.id)

        expect(redis).to have_received(:publish).with("timeline:#{follower.id}", anything)
      end
    end

    context 'with a private status' do
      before do
        status.update(visibility: :private)
      end

      it 'does not publish to the public timeline' do
        subject.perform(status.id)

        expect(redis).to_not have_received(:publish).with('timeline:public', anything)
      end

      it 'publishes to the status-specific channel' do
        subject.perform(status.id)

        expect(redis).to have_received(:publish).with("timeline:status:#{status.id}", anything)
      end
    end

    context 'with a status older than 7 days' do
      before do
        status.update(created_at: 8.days.ago, visibility: :public)
      end

      it 'still publishes to the status-specific channel' do
        subject.perform(status.id)

        expect(redis).to have_received(:publish).with("timeline:status:#{status.id}", anything)
      end

      it 'does not broadcast to timelines' do
        subject.perform(status.id)

        expect(redis).to_not have_received(:publish).with('timeline:public', anything)
        expect(redis).to_not have_received(:publish).with("timeline:#{follower.id}", anything)
      end
    end

    context 'with a suspended account' do
      before do
        account.update(suspended_at: Time.now.utc)
      end

      it 'does not publish anything' do
        subject.perform(status.id)

        expect(redis).to_not have_received(:publish)
      end
    end

    context 'with a silenced account' do
      before do
        account.update(silenced_at: Time.now.utc)
      end

      it 'does not publish anything' do
        subject.perform(status.id)

        expect(redis).to_not have_received(:publish)
      end
    end

    context 'when follower has muted the author' do
      before do
        Fabricate(:mute, account: follower, target_account: account)
        status.update(visibility: :public)
      end

      it 'does not publish to the muted follower' do
        subject.perform(status.id)

        expect(redis).to_not have_received(:publish).with("timeline:#{follower.id}", anything)
      end
    end

    context 'with a missing status' do
      it 'does not raise error' do
        expect { subject.perform(-1) }.to_not raise_error
      end
    end
  end
end
