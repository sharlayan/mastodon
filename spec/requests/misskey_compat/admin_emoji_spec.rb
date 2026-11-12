# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat admin emoji' do
  let(:role) { Fabricate(:user_role, permissions: UserRole::FLAGS[:manage_custom_emojis]) }
  let(:user) { Fabricate(:user, role: role) }
  let(:token) { MisskeyCompat::MiAuth.issue_native_token(user).token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  def api(path, **params)
    post "/api/#{path}", params: { i: token }.merge(params), as: :json
    response.parsed_body
  end

  def mid(record)
    MisskeyCompat::MiId.encode(record.id)
  end

  it 'adds, updates, lists and deletes local emoji with Mastodon action logs' do
    drive_file = DriveFile.create!(account: user.account, file: attachment_fixture('emojo.png'))

    added = api('admin/emoji/add', name: 'blob', fileId: mid(drive_file), category: 'Blobs', aliases: %w(b1), license: 'CC0', isSensitive: true)
    emoji = CustomEmoji.local.find_by!(shortcode: 'blob')
    expect(added).to include(name: 'blob', category: 'Blobs', aliases: %w(b1), license: 'CC0', isSensitive: true, localOnly: false, host: nil)
    expect(Admin::ActionLog.where(target: emoji, action: 'create')).to exist

    api('admin/emoji/add', name: 'blob', fileId: mid(drive_file))
    expect(response.parsed_body.dig(:error, :code)).to eq('DUPLICATE_NAME')

    api('admin/emoji/update', id: mid(emoji), name: 'blob2', localOnly: true, category: nil)
    expect(response).to have_http_status(204)
    expect(emoji.reload).to have_attributes(shortcode: 'blob2', local_only: true, category_id: nil)

    expect(api('admin/emoji/list', query: 'blob').pluck(:name)).to eq(%w(blob2))
    expect(api('admin/emoji/list', query: ':nothing:')).to eq([])

    api('admin/emoji/delete', id: mid(emoji))
    expect(response).to have_http_status(204)
    expect(CustomEmoji.exists?(emoji.id)).to be(false)
    expect(Admin::ActionLog.where(target_type: 'CustomEmoji', action: 'destroy')).to exist
  end

  it 'applies bulk alias, category and license updates to local emoji only' do
    first = Fabricate(:custom_emoji, aliases: %w(a))
    second = Fabricate(:custom_emoji, aliases: %w(b))
    remote = Fabricate(:custom_emoji, domain: 'remote.example', aliases: %w(r))
    ids = [mid(first), mid(second), mid(remote)]

    api('admin/emoji/add-aliases-bulk', ids: ids, aliases: %w(x))
    api('admin/emoji/remove-aliases-bulk', ids: ids, aliases: %w(a))
    api('admin/emoji/set-category-bulk', ids: ids, category: 'Shared')
    api('admin/emoji/set-license-bulk', ids: ids, license: 'MIT')

    expect([first.reload, second.reload].map(&:aliases)).to eq([%w(x), %w(b x)])
    expect([first, second].map { |emoji| [emoji.category&.name, emoji.license] }).to all(eq(%w(Shared MIT)))
    expect(remote.reload).to have_attributes(aliases: %w(r), category_id: nil, license: nil)

    api('admin/emoji/set-aliases-bulk', ids: [mid(first)], aliases: %w(only))
    expect(first.reload.aliases).to eq(%w(only))

    api('admin/emoji/delete-bulk', ids: [mid(first), mid(second)])
    expect(CustomEmoji.where(id: [first.id, second.id])).to be_empty
  end

  it 'lists and copies remote emoji and serves the v2 admin list' do
    remote = Fabricate(:custom_emoji, shortcode: 'party', domain: 'remote.example', license: 'CC-BY')
    Fabricate(:custom_emoji, shortcode: 'local_one')

    expect(api('admin/emoji/list-remote', host: 'remote.example').pluck(:name)).to eq(%w(party))

    copied = api('admin/emoji/copy', emojiId: mid(remote))
    expect(CustomEmoji.local.find(MisskeyCompat::MiId.decode(copied[:id]))).to have_attributes(shortcode: 'party', license: 'CC-BY')
    api('admin/emoji/copy', emojiId: mid(remote))
    expect(response.parsed_body.dig(:error, :code)).to eq('DUPLICATE_NAME')

    result = api('v2/admin/emoji/list', query: { hostType: 'local' }, sortKeys: %w(+name), limit: 1)
    expect(result).to include(allCount: 2, allPages: 2, count: 1)
    expect(result[:emojis].sole).to include(name: 'local_one', host: nil, roleIdsThatCanBeUsedThisEmojiAsReaction: [])

    api('v2/admin/emoji/list', sortKeys: %w(+nope))
    expect(response).to have_http_status(400)
  end

  it 'imports Misskey emoji zip archives in place and requires the native token' do
    zip_path = Rails.root.join('tmp', "misskey_emoji_#{SecureRandom.hex(4)}.zip")
    Zip::File.open(zip_path, create: true) do |zip|
      zip.get_output_stream('meta.json') { |io| io.write({ emojis: [{ downloaded: true, fileName: 'neko.png', emoji: { name: 'neko', category: 'Cats', aliases: %w(cat) } }] }.to_json) }
      zip.get_output_stream('neko.png') { |io| io.write(Rails.root.join('spec', 'fixtures', 'files', 'emojo.png').binread) }
    end
    existing = Fabricate(:custom_emoji, shortcode: 'neko')
    Setting.drive_allowed_extensions = 'zip'
    drive_file = DriveFile.create!(account: user.account, file: Rack::Test::UploadedFile.new(zip_path, 'application/zip'))

    post '/api/admin/emoji/import-zip', params: { i: MisskeyCompat::MiAuth.issue_token(user, permission: 'read:account').token, fileId: mid(drive_file) }, as: :json
    expect(response).to have_http_status(403)

    api('admin/emoji/import-zip', fileId: mid(drive_file))
    expect(response).to have_http_status(204)
    MisskeyCompatEmojiImportWorker.drain

    expect(existing.reload).to have_attributes(aliases: %w(cat), category: have_attributes(name: 'Cats'))
  ensure
    FileUtils.rm_f(zip_path)
  end

  it 'denies users without the custom emoji permission' do
    plain = Fabricate(:user)
    post '/api/admin/emoji/list', params: { i: MisskeyCompat::MiAuth.issue_native_token(plain).token }, as: :json

    expect(response).to have_http_status(403)
    expect(response.parsed_body.dig(:error, :id)).to eq('7f86f06f-7e15-4057-8561-f4b6d4ac755a')
  end
end
