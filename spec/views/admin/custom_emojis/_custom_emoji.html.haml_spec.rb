# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'admin/custom_emojis/_custom_emoji.html.haml' do
  let(:form) { instance_double(ActionView::Helpers::FormHelper, check_box: nil) }

  context 'with a local emoji' do
    let(:custom_emoji) do
      Fabricate(
        :custom_emoji,
        aliases: %w(blob cute),
        disabled: false,
        domain: nil,
        shortcode: 'blobcat',
        visible_in_picker: true
      )
    end

    it 'renders aliases, local state, and the edit action' do
      render partial: 'admin/custom_emojis/custom_emoji', locals: { custom_emoji:, f: form }

      expect(rendered).to include(':blobcat:', 'blob', 'cute')
      expect(rendered).to include(I18n.t('admin.custom_emojis.enabled'))
      expect(rendered).to include(I18n.t('admin.custom_emojis.listed'))
      expect(rendered).to include(I18n.t('admin.accounts.location.local'))
      expect(rendered).to include(edit_admin_custom_emoji_path(custom_emoji))
    end
  end

  context 'with a remote emoji' do
    let(:custom_emoji) do
      Fabricate(
        :custom_emoji,
        aliases: %w(blob cute),
        disabled: true,
        domain: 'remote.example',
        shortcode: 'blobcat'
      )
    end

    it 'retains the upstream remote row layout' do
      render partial: 'admin/custom_emojis/custom_emoji', locals: { custom_emoji:, f: form }

      expect(rendered).to include(':blobcat:', 'blob, cute', 'remote.example')
      expect(rendered).to include(I18n.t('admin.custom_emojis.disabled'))
      expect(rendered).to_not include(edit_admin_custom_emoji_path(custom_emoji))
    end
  end
end
