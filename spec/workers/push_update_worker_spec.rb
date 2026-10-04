# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PushUpdateWorker do
  let(:worker) { described_class.new }

  describe 'perform' do
    context 'with missing values' do
      it 'runs without error' do
        expect { worker.perform(nil, nil) }
          .to_not raise_error
      end
    end

    context 'with valid records' do
      let(:account) { Fabricate :account }
      let(:status) { Fabricate :status, text: 'Test Post' }

      before { allow(redis).to receive(:publish) }

      it 'pushes message to timeline' do
        expect { worker.perform(account.id, status.id) }
          .to_not raise_error

        expect(redis)
          .to have_received(:publish)
          .with(
            redis_key,
            match_json_values(
              event: 'update',
              payload: include(
                created_at: status.created_at.iso8601(3),
                content: eq('<p>Test Post</p>')
              )
            )
          )
      end

      it 'does not load the recipient account without a Misskey subscription' do
        allow(redis).to receive(:exists?).with("subscribed:misskey:timeline:#{account.id}").and_return(false)
        allow(Account).to receive(:find_by).and_call_original

        worker.perform(account.id, status.id)

        expect(Account).to_not have_received(:find_by).with(id: account.id)
      end

      def redis_key
        "timeline:#{account.id}"
      end
    end
  end
end
