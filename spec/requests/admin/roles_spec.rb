# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Roles' do
  context 'when signed in as lower permissions user' do
    let(:user_role) { Fabricate(:user_role, permissions: UserRole::Flags::NONE) }

    before { sign_in Fabricate(:user, role: user_role) }

    describe 'GET /admin/roles' do
      it 'returns http forbidden' do
        get admin_roles_path

        expect(response)
          .to have_http_status(403)
      end
    end

    describe 'GET /admin/roles/new' do
      it 'returns http forbidden' do
        get new_admin_role_path

        expect(response)
          .to have_http_status(403)
      end
    end

    describe 'GET /admin/roles/:id/edit' do
      let(:role) { Fabricate(:user_role) }

      it 'returns http forbidden' do
        get edit_admin_role_path(role)

        expect(response)
          .to have_http_status(403)
      end
    end

    describe 'PUT /admin/roles/:id' do
      let(:role) { Fabricate(:user_role) }

      it 'returns http forbidden' do
        put admin_role_path(role)

        expect(response)
          .to have_http_status(403)
      end
    end

    describe 'DELETE /admin/roles/:id' do
      let(:role) { Fabricate(:user_role) }

      it 'returns http forbidden' do
        delete admin_role_path(role)

        expect(response)
          .to have_http_status(403)
      end
    end
  end

  context 'when user has permissions to manage roles' do
    let(:user_role) { Fabricate(:user_role, permissions: UserRole::FLAGS[:manage_users]) }

    before { sign_in Fabricate(:user, role: user_role) }

    context 'when target role permission outranks user' do
      let(:role) { Fabricate(:user_role, position: user_role.position + 1) }

      describe 'GET /admin/roles/:id/edit' do
        it 'returns http forbidden' do
          get edit_admin_role_path(role)

          expect(response)
            .to have_http_status(403)
        end
      end

      describe 'PUT /admin/roles/:id' do
        it 'returns http forbidden' do
          put admin_role_path(role)

          expect(response)
            .to have_http_status(403)
        end
      end

      describe 'DELETE /admin/roles/:id' do
        it 'returns http forbidden' do
          delete admin_role_path(role)

          expect(response)
            .to have_http_status(403)
        end
      end
    end
  end

  context 'when attempting to add permissions the user does not have' do
    let(:user_role) { Fabricate(:user_role, permissions: UserRole::FLAGS[:manage_roles], position: 5) }

    before { sign_in Fabricate(:user, role: user_role) }

    describe 'POST /admin/roles' do
      subject { post admin_roles_path, params: { user_role: { name: 'Bar', position: 2, permissions_as_keys: %w(manage_roles manage_users manage_reports) } } }

      it 'does not create role' do
        expect { subject }
          .to_not change(UserRole, :count)

        expect(response.body)
          .to include(I18n.t('admin.roles.add_new'))
      end
    end

    describe 'PUT /admin/roles/:id' do
      subject { put admin_role_path(role), params: { user_role: { position: 2, permissions_as_keys: %w(manage_roles manage_users manage_reports) } } }

      let(:role) { Fabricate(:user_role, name: 'Bar') }

      it 'does not create role' do
        expect { subject }
          .to_not(change { role.reload.permissions })

        expect(response.parsed_body.title)
          .to match(I18n.t('admin.roles.edit', name: 'Bar'))
      end
    end
  end

  context 'when signed in as admin' do
    before { sign_in Fabricate(:admin_user) }

    describe 'GET /admin/roles/new' do
      it 'hides the management timeline permission outside roleplay mode' do
        ClimateControl.modify(OC_ROLEPLAY_OPTION: 'false') do
          get new_admin_role_path
        end

        expect(response).to have_http_status(200)
        expect(response.body).to_not include('view_admin_timeline')
      end

      it 'shows the management timeline permission in roleplay mode' do
        ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') do
          get new_admin_role_path
        end

        expect(response).to have_http_status(200)
        expect(response.body).to include('view_admin_timeline')
      end
    end

    describe 'POST /admin/roles' do
      it 'creates a role with a drive quota' do
        expect do
          post admin_roles_path, params: { user_role: { name: 'Drive role', position: 0, drive_quota: 2048 } }
        end.to change(UserRole, :count).by(1)

        expect(UserRole.order(:id).last.drive_quota).to eq(2048)
      end

      it 'gracefully handles invalid nested params' do
        post admin_roles_path(user_role: 'invalid')

        expect(response)
          .to have_http_status(400)
      end

      it 'does not assign the management timeline permission outside roleplay mode' do
        ClimateControl.modify(OC_ROLEPLAY_OPTION: 'false') do
          post admin_roles_path, params: { user_role: { name: 'Normal role', position: 2, extra_permissions_as_keys: %w(view_admin_timeline) } }
        end

        expect(UserRole.find_by(name: 'Normal role').can_extra?(:view_admin_timeline)).to be(false)
      end
    end
  end

  describe 'POST /admin/roles assigning the management timeline permission in roleplay mode' do
    around do |example|
      ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') { example.run }
    end

    before { sign_in Fabricate(:user, role: acting_role) }

    let(:acting_role) do
      Fabricate(:user_role, name: 'Acting role', position: acting_position, permissions_as_keys: acting_permissions, extra_permissions_as_keys: acting_extra_permissions)
    end

    let(:created_role) { UserRole.find_by(name: 'Community role') }

    def create_community_role
      post admin_roles_path, params: { user_role: { name: 'Community role', position: 2, extra_permissions_as_keys: %w(view_admin_timeline) } }
    end

    context 'when an administrator lacks the management timeline permission' do
      let(:acting_position) { 100 }
      let(:acting_permissions) { %w(manage_roles) }
      let(:acting_extra_permissions) { [] }

      it 'refuses to elevate the new role beyond the grantor' do
        create_community_role

        expect(created_role).to be_nil
      end
    end

    context 'when an administrator holds the management timeline permission' do
      let(:acting_position) { 100 }
      let(:acting_permissions) { %w(manage_roles) }
      let(:acting_extra_permissions) { %w(view_admin_timeline) }

      it 'assigns the permission to the new role' do
        create_community_role

        expect(created_role.can_extra?(:view_admin_timeline)).to be(true)
      end
    end

    context 'when a moderator lacks the management timeline permission' do
      let(:acting_position) { 10 }
      let(:acting_permissions) { %w(manage_users) }
      let(:acting_extra_permissions) { [] }

      it 'forbids creating the role' do
        create_community_role

        expect(response).to have_http_status(403)
        expect(created_role).to be_nil
      end
    end

    context 'when a moderator holds the management timeline permission' do
      let(:acting_position) { 10 }
      let(:acting_permissions) { %w(manage_users) }
      let(:acting_extra_permissions) { %w(view_admin_timeline) }

      it 'forbids creating the role despite holding the permission' do
        create_community_role

        expect(response).to have_http_status(403)
        expect(created_role).to be_nil
      end
    end
  end
end
