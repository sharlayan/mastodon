# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Status do
  describe '.not_domain_muted_by_account' do
    subject { described_class.not_domain_muted_by_account(account).pluck(:id) }

    let(:account) { Fabricate(:account) }
    let(:muted_account) { Fabricate(:account, domain: 'muted.example', username: 'alice') }
    let(:other_account) { Fabricate(:account, domain: 'other.example', username: 'bob') }

    let!(:muted_status) { Fabricate(:status, account: muted_account) }
    let!(:other_status) { Fabricate(:status, account: other_account) }
    let!(:muted_status_reblog) { Fabricate(:status, account: other_account, reblog: muted_status) }
    let!(:local_status) { Fabricate(:status, account: account) }

    context 'without any domain mute' do
      it 'includes every status' do
        expect(subject).to include(muted_status.id, other_status.id, muted_status_reblog.id, local_status.id)
      end
    end

    context 'with a muted domain' do
      before { account.mute_domain!('muted.example') }

      it 'excludes statuses from the muted domain' do
        expect(subject).to_not include(muted_status.id)
        expect(subject).to include(other_status.id, local_status.id)
      end

      it 'excludes reblogs of statuses from the muted domain' do
        expect(subject).to_not include(muted_status_reblog.id)
      end

      context 'when the account follows someone on the muted domain' do
        before { account.follow!(muted_account) }

        it 'keeps statuses from the followed account' do
          expect(subject).to include(muted_status.id, muted_status_reblog.id)
        end
      end
    end
  end
end
