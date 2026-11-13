# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat admin system information' do
  let(:role) { Fabricate(:user_role, permissions: UserRole::FLAGS[:view_devops]) }
  let(:user) { Fabricate(:user, role: role) }
  let(:token) { MisskeyCompat::MiAuth.issue_native_token(user).token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  def api(path)
    post "/api/admin/#{path}", params: { i: token }, as: :json
    response.parsed_body
  end

  it 'returns real server, index and table metrics to devops roles' do
    info = api('server-info')
    expect(info).to include(machine: Socket.gethostname, psql: be_present, redis: be_present, cpu: include(cores: Etc.nprocessors), mem: include(total: be_positive))

    expect(api('get-index-stats')).to include(include(tablename: 'accounts', indexname: 'accounts_pkey'))
    expect(api('get-table-stats')[:accounts]).to include(:count, size: be_positive)
  end

  it 'keeps the metrics away from roles without devops access and public server-info empty' do
    user.update!(role: Fabricate(:user_role, permissions: UserRole::FLAGS[:manage_settings]))

    api('get-table-stats')
    expect(response.parsed_body.dig(:error, :id)).to eq('c3d38592-54c0-429d-be96-5636b0431a61')

    api('server-info')
    expect(response.parsed_body.dig(:error, :id)).to eq('d33d5333-db36-423d-a8f9-1a2b9549da41')

    post '/api/server-info', as: :json
    expect(response.parsed_body).to include(machine: '?', mem: { total: 0 })
  end
end
