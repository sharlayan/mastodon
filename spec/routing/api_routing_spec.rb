# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API routes' do
  describe 'Credentials routes' do
    it 'routes to verify credentials' do
      expect(get('/api/v1/accounts/verify_credentials'))
        .to route_to('api/v1/accounts/credentials#show')
    end

    it 'routes to update credentials' do
      expect(patch('/api/v1/accounts/update_credentials'))
        .to route_to('api/v1/accounts/credentials#update')
    end
  end

  describe 'Account routes' do
    it 'routes to statuses' do
      expect(get('/api/v1/accounts/user/statuses'))
        .to route_to('api/v1/accounts/statuses#index', account_id: 'user')
    end

    it 'routes to followers' do
      expect(get('/api/v1/accounts/user/followers'))
        .to route_to('api/v1/accounts/follower_accounts#index', account_id: 'user')
    end

    it 'routes to following' do
      expect(get('/api/v1/accounts/user/following'))
        .to route_to('api/v1/accounts/following_accounts#index', account_id: 'user')
    end

    it 'routes to search' do
      expect(get('/api/v1/accounts/search'))
        .to route_to('api/v1/accounts/search#show')
    end

    it 'routes to relationships' do
      expect(get('/api/v1/accounts/relationships'))
        .to route_to('api/v1/accounts/relationships#index')
    end
  end

  describe 'Statuses routes' do
    it 'routes reblogged_by' do
      expect(get('/api/v1/statuses/123/reblogged_by'))
        .to route_to('api/v1/statuses/reblogged_by_accounts#index', status_id: '123')
    end

    it 'routes favourited_by' do
      expect(get('/api/v1/statuses/123/favourited_by'))
        .to route_to('api/v1/statuses/favourited_by_accounts#index', status_id: '123')
    end

    it 'routes reblog' do
      expect(post('/api/v1/statuses/123/reblog'))
        .to route_to('api/v1/statuses/reblogs#create', status_id: '123')
    end

    it 'routes unreblog' do
      expect(post('/api/v1/statuses/123/unreblog'))
        .to route_to('api/v1/statuses/reblogs#destroy', status_id: '123')
    end

    it 'routes favourite' do
      expect(post('/api/v1/statuses/123/favourite'))
        .to route_to('api/v1/statuses/favourites#create', status_id: '123')
    end

    it 'routes unfavourite' do
      expect(post('/api/v1/statuses/123/unfavourite'))
        .to route_to('api/v1/statuses/favourites#destroy', status_id: '123')
    end

    it 'routes mute' do
      expect(post('/api/v1/statuses/123/mute'))
        .to route_to('api/v1/statuses/mutes#create', status_id: '123')
    end

    it 'routes unmute' do
      expect(post('/api/v1/statuses/123/unmute'))
        .to route_to('api/v1/statuses/mutes#destroy', status_id: '123')
    end

    it 'routes reactions containing a domain suffix' do
      expect(post('/api/v1/statuses/123/react/blob@example.com'))
        .to route_to('api/v1/statuses/reactions#create', status_id: '123', id: 'blob@example.com')
    end
  end

  describe 'Timeline routes' do
    it 'routes to home timeline' do
      expect(get('/api/v1/timelines/home'))
        .to route_to('api/v1/timelines/home#show')
    end

    it 'routes to public timeline' do
      expect(get('/api/v1/timelines/public'))
        .to route_to('api/v1/timelines/public#show')
    end

    it 'routes to tag timeline' do
      expect(get('/api/v1/timelines/tag/test'))
        .to route_to('api/v1/timelines/tag#show', id: 'test')
    end

    it 'routes to an antenna timeline' do
      expect(get('/api/v1/timelines/antenna/123'))
        .to route_to('api/v1/timelines/antenna#show', id: '123')
    end
  end

  describe 'Sharlayan collection routes' do
    it 'routes clip favourites before clip identifiers' do
      expect(get('/api/v1/clips/favourites'))
        .to route_to('api/v1/clips/favourites#index')
    end

    it 'routes drive file lookup before file identifiers' do
      expect(get('/api/v1/drive/files/find'))
        .to route_to('api/v1/drive/files#find')
    end

    it 'routes account pages by name' do
      expect(get('/api/v1/accounts/123/pages/example'))
        .to route_to('api/v1/accounts/pages#show', account_id: '123', name: 'example')
    end

    it 'keeps Misskey admin stubs inside the compatibility namespace' do
      expect(post('/api/admin/example'))
        .to route_to('api/misskey_compat/stub#noop', any: 'example')
    end
  end
end
