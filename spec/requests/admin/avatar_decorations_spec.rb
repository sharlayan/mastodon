# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Avatar Decorations' do
  let(:long_name) { 'c' * 101 }

  before do
    Setting.avatar_decorations_enabled = true
    sign_in Fabricate(:admin_user)
  end

  describe 'POST /admin/avatar_decorations' do
    it 'shows a validation error for an overlong new category name' do
      expect do
        post admin_avatar_decorations_path, params: {
          avatar_decoration: { name: 'ring', image: fixture_file_upload('emojo.png', 'image/png'), category_name: long_name },
        }
      end.to_not change(AvatarDecoration, :count)

      expect(response).to have_http_status(200)
      expect(AvatarDecorationCategory.where(name: long_name)).to_not exist
    end

    it 'creates the decoration in a new category' do
      post admin_avatar_decorations_path, params: {
        avatar_decoration: { name: 'ring', image: fixture_file_upload('emojo.png', 'image/png'), category_name: ' Seasonal ' },
      }

      expect(response).to redirect_to(admin_avatar_decorations_path)
      expect(AvatarDecoration.find_by(name: 'ring').category.name).to eq 'Seasonal'
    end
  end

  describe 'PUT /admin/avatar_decorations/:id' do
    let(:decoration) { Fabricate(:avatar_decoration, name: 'ring') }

    it 'shows a validation error for an overlong new category name' do
      put admin_avatar_decoration_path(decoration), params: { avatar_decoration: { name: 'renamed', category_name: long_name } }

      expect(response).to have_http_status(200)
      expect(decoration.reload.name).to eq 'ring'
    end
  end

  describe 'POST /admin/avatar_decorations/batch' do
    let(:decoration) { Fabricate(:avatar_decoration) }

    it 'reports an overlong new category name instead of failing' do
      post batch_admin_avatar_decorations_path, params: {
        update: '1',
        form_avatar_decoration_batch: { avatar_decoration_ids: [decoration.id], category_name: long_name },
      }

      expect(response).to have_http_status(302)
      expect(flash[:alert]).to be_present
      expect(decoration.reload.category_id).to be_nil
    end
  end
end
