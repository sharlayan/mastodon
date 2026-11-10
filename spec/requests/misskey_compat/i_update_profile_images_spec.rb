# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat i/update profile images' do
  let(:user)    { Fabricate(:user) }
  let(:account) { user.account }
  let(:token)   { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write').token }

  around do |example|
    drive_enabled = Setting.drive_enabled
    example.run
  ensure
    Setting.drive_enabled = drive_enabled
  end

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  def update(**body)
    post '/api/i/update', params: { i: token, **body }, as: :json
  end

  def error
    response.parsed_body[:error]
  end

  context 'when Drive is enabled' do
    before { Setting.drive_enabled = true }

    let(:drive_file) { account.drive_files.create!(file: attachment_fixture('attachment.jpg')) }

    it 'sets the avatar and banner from Drive file ids' do
      id = MisskeyCompat::MiId.encode(drive_file.id)

      update(avatarId: id, bannerId: id)

      expect(response).to have_http_status(200)
      account.reload
      expect(account.avatar_file_name).to be_present
      expect(account.header_file_name).to be_present
    end

    it "rejects a Drive file that is not an image and another account's Drive file" do
      video_file = account.drive_files.create!(file: attachment_fixture('attachment.webm'))
      previous = account.avatar_file_name

      update(avatarId: MisskeyCompat::MiId.encode(video_file.id))

      expect(response).to have_http_status(400)
      expect(error).to include(code: 'AVATAR_NOT_AN_IMAGE', id: 'f419f9f8-2f4d-46b1-9fb4-49d3a2fd7191')
      expect(account.reload.avatar_file_name).to eq(previous)

      other = Fabricate(:account).drive_files.create!(file: attachment_fixture('attachment.jpg'))

      update(bannerId: MisskeyCompat::MiId.encode(other.id))

      expect(response).to have_http_status(400)
      expect(error).to include(code: 'NO_SUCH_BANNER', id: '0d8f5629-f210-41c2-9433-735831a58595')
    end
  end

  it 'returns NO_SUCH_AVATAR and NO_SUCH_BANNER for unknown ids without changing anything' do
    update(name: 'Changed', avatarId: MisskeyCompat::MiId.encode(999_999_999))

    expect(response).to have_http_status(400)
    expect(error).to include(code: 'NO_SUCH_AVATAR', id: '539f3a45-f215-4f81-a9a8-31293640207f')
    expect(account.reload.display_name).to_not eq('Changed')

    update(bannerId: MisskeyCompat::MiId.encode(999_999_999))

    expect(response).to have_http_status(400)
    expect(error).to include(code: 'NO_SUCH_BANNER')
  end

  it 'rejects a non-image media attachment as a banner and a non-string id' do
    video = Fabricate(:media_attachment, account: account, type: :video, file: attachment_fixture('attachment.webm'))

    update(bannerId: MisskeyCompat::MiId.encode(video.id))

    expect(response).to have_http_status(400)
    expect(error).to include(code: 'BANNER_NOT_AN_IMAGE', id: '75aedb19-2afd-4e6d-87fc-67941256fa60')

    image = Fabricate(:media_attachment, account: account)

    update(avatarId: [image.id.to_s])

    expect(response).to have_http_status(400)
    expect(error).to include(code: 'INVALID_PARAM')
    expect(account.reload.avatar_file_name).to be_nil
  end
end
