# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Sharlayan routes' do
  it 'routes public compatibility and media endpoints' do
    expect(get: '/nodeinfo/2.1').to route_to('well_known/node_info#show_two_one')
    expect(get: '/proxy/https://remote.example/image.png').to route_to(
      controller: 'misskey_compat/media_proxy',
      action: 'show',
      any: 'https://remote.example/image.png'
    )
    expect(get: '/drive_media/access-key/small').to route_to(
      controller: 'drive_media',
      action: 'show',
      id: 'access-key',
      style: 'small'
    )
  end

  it 'routes custom web application paths' do
    expect(get: '/antennas').to route_to('home#index')
    expect(get: '/conversations/123').to route_to(controller: 'home', action: 'index', any: '123')
    expect(get: '/pages/featured').to route_to(controller: 'home', action: 'index', any: 'featured')
  end

  it 'loads the management timeline web route only in roleplay mode' do
    if ENV['OC_ROLEPLAY_OPTION'] == 'true'
      expect(get: '/timelines/admin').to route_to('home#index')
    else
      expect(get: '/timelines/admin').to route_to(
        controller: 'application',
        action: 'raise_not_found',
        unmatched_route: 'timelines/admin'
      )
    end
  end

  it 'routes custom administration resources' do
    expect(get: '/admin/drive/files').to route_to('admin/drive_files#index')
    expect(post: '/admin/board_announcements/1/publish').to route_to(
      controller: 'admin/board_announcements',
      action: 'publish',
      id: '1'
    )
    expect(get: '/admin/avatar_decorations').to route_to('admin/avatar_decorations#index')
  end

  it 'routes multi-account authentication' do
    expect(get: '/multi_accounts/entry').to route_to('multi_accounts/entries#show')
    expect(post: '/multi_accounts/auth/verify_otp').to route_to('multi_accounts/auth#verify_otp')
  end
end
