# frozen_string_literal: true

require 'rails_helper'

RSpec.describe HideStatusWorker do
  subject { described_class.new.perform(status.id, { 'hidden_by_account_id' => status.account_id }) }

  let(:status) { Fabricate(:status) }

  around do |example|
    ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') { example.run }
  end

  after { Setting.soft_hide_deletion = false }

  it 'soft-hides the status while soft-hide deletion is enabled' do
    Setting.soft_hide_deletion = true

    subject

    expect(RpHiddenStatus.exists?(status_id: status.id)).to be(true)
  end

  it 'deletes the status when soft-hide deletion was disabled after the request' do
    Setting.soft_hide_deletion = false

    subject

    expect(Status.with_discarded.unscoped.find_by(id: status.id)).to be_nil
  end
end
