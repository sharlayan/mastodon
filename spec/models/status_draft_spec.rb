# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StatusDraft do
  let(:account) { Fabricate(:account) }

  it 'rejects draft data above the per-item byte limit' do
    draft = Fabricate.build(:status_draft, account: account, data: { status: 'x' * described_class::MAX_DATA_BYTES })

    expect(draft).to_not be_valid
    expect(draft.errors).to include(:data)
  end

  it 'rejects writes that would exceed the account storage quota' do
    existing = Fabricate(:status_draft, account: account)
    existing.update_column(:data, { status: 'x' * described_class::MAX_ACCOUNT_DATA_BYTES })
    draft = Fabricate.build(:status_draft, account: account, data: { status: 'small' })

    expect(draft).to_not be_valid
    expect(draft.errors[:base]).to include(I18n.t('status_drafts.storage_too_large', limit: described_class::MAX_ACCOUNT_DATA_BYTES / 1.megabyte))
  end

  it 'allows an oversized legacy draft to be reduced below the limits' do
    draft = Fabricate(:status_draft, account: account)
    draft.update_column(:data, { status: 'x' * described_class::MAX_ACCOUNT_DATA_BYTES })

    draft.data = { status: 'reduced' }

    expect(draft).to be_valid
  end
end
