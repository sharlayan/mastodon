# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MisskeyCompatReversiActionWorker do
  let(:worker)  { described_class.new }
  let(:service) { instance_double(MisskeyCompat::ReversiService, ready: nil, update_settings: nil, cancel_game: nil, put_stone: nil, check_timeout: nil, start_game: nil) }
  let(:account) { Fabricate(:user).account }

  before do
    Setting.misskey_compat_enabled = true
    allow(MisskeyCompat::ReversiService).to receive(:new).and_return(service)
  end

  after { Setting.misskey_compat_enabled = false }

  it 'dispatches valid stream actions from active local accounts to the service' do
    worker.perform(account.id.to_s, '9', 'ready', true)
    worker.perform(account.id.to_s, '9', 'updateSettings', { 'key' => 'bw', 'value' => '1' })
    worker.perform(account.id.to_s, '9', 'cancel', nil)
    worker.perform(account.id.to_s, '9', 'putStone', { 'pos' => 19, 'id' => 'op' })
    worker.perform(account.id.to_s, '9', 'claimTimeIsUp', {})
    worker.perform(nil, '9', 'start')

    expect(service).to have_received(:ready).with('9', account, true)
    expect(service).to have_received(:update_settings).with('9', account, 'bw', '1')
    expect(service).to have_received(:cancel_game).with('9', account)
    expect(service).to have_received(:put_stone).with('9', account, 19, 'op')
    expect(service).to have_received(:check_timeout).with('9')
    expect(service).to have_received(:start_game).with('9')
  end

  it 'ignores malformed bodies, unavailable accounts and a disabled compatibility layer' do
    worker.perform(account.id.to_s, '9', 'ready', 'yes')
    worker.perform(account.id.to_s, '9', 'putStone', { 'pos' => '19', 'id' => 'op' })
    worker.perform(Fabricate(:account, domain: 'remote.example').id.to_s, '9', 'cancel', nil)
    account.user.update!(disabled: true)
    worker.perform(account.id.to_s, '9', 'cancel', nil)
    Setting.misskey_compat_enabled = false
    worker.perform(nil, '9', 'start')

    expect(service).to_not have_received(:ready)
    expect(service).to_not have_received(:put_stone)
    expect(service).to_not have_received(:cancel_game)
    expect(service).to_not have_received(:start_game)
  end
end
