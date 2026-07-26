# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Custom Emojis' do
  describe 'POST /admin/custom_emojis' do
    before { sign_in Fabricate(:admin_user) }

    it 'gracefully handles invalid nested params' do
      post admin_custom_emojis_path(custom_emoji: 'invalid')

      expect(response)
        .to have_http_status(400)
    end
  end

  describe 'GET /admin/custom_emojis/:id/edit' do
    let(:admin) { Fabricate(:admin_user) }
    let(:custom_emoji) { Fabricate(:custom_emoji, domain: nil) }

    before { sign_in admin }

    it 'returns http success' do
      get edit_admin_custom_emoji_path(custom_emoji)

      expect(response).to have_http_status(200)
    end

    it 'does not include a shortcode input field' do
      get edit_admin_custom_emoji_path(custom_emoji)

      expect(response.body).to_not include('name="custom_emoji[shortcode]"')
    end
  end

  describe 'PATCH /admin/custom_emojis/:id' do
    let(:admin) { Fabricate(:admin_user) }
    let(:custom_emoji) { Fabricate(:custom_emoji, domain: nil, shortcode: 'blobcat') }

    before { sign_in admin }

    context 'when updating aliases and license' do
      it 'updates the record and redirects' do
        patch admin_custom_emoji_path(custom_emoji), params: {
          custom_emoji: { aliases_raw: 'blob, cat, cute', license: 'CC0' },
        }

        expect(response).to redirect_to(admin_custom_emojis_path)
        custom_emoji.reload
        expect(custom_emoji.aliases).to contain_exactly('blob', 'cat', 'cute')
        expect(custom_emoji.license).to eq('CC0')
      end

      it 'updates the sensitive flag' do
        patch admin_custom_emoji_path(custom_emoji), params: {
          custom_emoji: { is_sensitive: '1' },
        }

        expect(custom_emoji.reload).to be_is_sensitive
      end

      it 'updates the local-only flag' do
        patch admin_custom_emoji_path(custom_emoji), params: {
          custom_emoji: { local_only: '1' },
        }

        expect(custom_emoji.reload).to be_local_only
      end

      it 'strips whitespace from aliases' do
        patch admin_custom_emoji_path(custom_emoji), params: {
          custom_emoji: { aliases_raw: '  blob ,  cat  , ' },
        }

        custom_emoji.reload
        expect(custom_emoji.aliases).to contain_exactly('blob', 'cat')
      end

      it 'clears aliases when blank is submitted' do
        custom_emoji.update!(aliases: ['blob'])

        patch admin_custom_emoji_path(custom_emoji), params: {
          custom_emoji: { aliases_raw: '' },
        }

        custom_emoji.reload
        expect(custom_emoji.aliases).to be_empty
      end
    end

    context 'when attempting to change the shortcode' do
      it 'ignores the shortcode parameter and preserves the original' do
        patch admin_custom_emoji_path(custom_emoji), params: {
          custom_emoji: { shortcode: 'changed', aliases_raw: '' },
        }

        custom_emoji.reload
        expect(custom_emoji.shortcode).to eq('blobcat')
      end
    end

    context 'when the record is invalid' do
      it 'renders edit form' do
        emoji = CustomEmoji.find(custom_emoji.id)
        allow(CustomEmoji).to receive(:find).and_return(emoji)
        allow(emoji).to receive(:update).and_return(false)

        patch admin_custom_emoji_path(custom_emoji), params: {
          custom_emoji: { aliases_raw: 'blob' },
        }

        expect(response).to have_http_status(200)
      end
    end
  end

  describe 'CustomEmoji.search with aliases' do
    before { sign_in Fabricate(:admin_user) }

    it 'finds emojis by alias' do
      Fabricate(:custom_emoji, shortcode: 'blobcat', aliases: ['fluffy', 'cute'])
      Fabricate(:custom_emoji, shortcode: 'cooldog', aliases: [])

      results = CustomEmoji.search('fluffy')
      expect(results.map(&:shortcode)).to include('blobcat')
      expect(results.map(&:shortcode)).to_not include('cooldog')
    end

    it 'still finds emojis by shortcode' do
      Fabricate(:custom_emoji, shortcode: 'blobcat', aliases: [])

      results = CustomEmoji.search('blob')
      expect(results.map(&:shortcode)).to include('blobcat')
    end
  end
end
