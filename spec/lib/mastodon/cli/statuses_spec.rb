# frozen_string_literal: true

require 'rails_helper'
require 'mastodon/cli/statuses'

RSpec.describe Mastodon::CLI::Statuses do
  subject { cli.invoke(action, arguments, options) }

  let(:cli) { described_class.new }
  let(:arguments) { [] }
  let(:options) { {} }

  it_behaves_like 'CLI Command'

  describe '#remove', use_transactional_tests: false do
    let(:action) { :remove }

    context 'with small batch size' do
      let(:options) { { batch_size: 0 } }

      it 'exits with error message' do
        expect { subject }
          .to raise_error(Thor::Error, /Cannot run/)
      end
    end

    context 'with default batch size' do
      it 'removes unreferenced statuses' do
        expect { subject }
          .to output_results('Done after')
      end
    end

    context 'with reactions on old remote statuses' do
      let(:options) { { skip_media_remove: true } }
      let(:remote_account) { Fabricate(:account, domain: 'example.com') }
      let(:local_account) { Fabricate(:account) }

      after do
        remote_account.statuses.destroy_all
        local_account.destroy!
        remote_account.destroy!
        Instance.refresh
      end

      it 'preserves local reactions while removing statuses with only remote reactions or no references' do
        statuses = Array.new(3) do |index|
          Fabricate(:status, account: remote_account, id: Mastodon::Snowflake.id_at(100.days.ago, with_random: false) + index, created_at: 100.days.ago)
        end
        Fabricate(:status_reaction, status: statuses.first, account: local_account, custom_emoji: nil)
        Fabricate(:status_reaction, status: statuses.second, account: remote_account, custom_emoji: nil)

        expect { subject }.to output_results('Done after')

        expect(Status.where(id: statuses.map(&:id)).pluck(:id)).to eq [statuses.first.id]
        expect(statuses.first.status_reactions.pluck(:account_id)).to eq [local_account.id]
      end
    end
  end
end
