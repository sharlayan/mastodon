# frozen_string_literal: true

require 'rails_helper'

RSpec.describe REST::AccountSerializer do
  subject do
    serialized_record_json(account, described_class, options: {
      scope: current_user,
      scope_name: :current_user,
    })
  end

  let(:default_datetime) { DateTime.new(2024, 11, 28, 16, 20, 0) }
  let(:role)    { Fabricate(:user_role, name: 'Role', highlighted: true) }
  let(:user)    { Fabricate(:user, role: role) }
  let(:account) { user.account }
  let(:current_user) { Fabricate(:user) }

  context 'when the account is suspended' do
    before do
      account.suspend!
    end

    it 'returns empty roles' do
      expect(subject['roles']).to eq []
    end
  end

  context 'when the account has a highlighted role' do
    let(:role) { Fabricate(:user_role, name: 'Role', highlighted: true) }

    it 'returns the expected role' do
      expect(subject['roles'].first).to include({ 'name' => 'Role' })
    end
  end

  context 'when the account has a non-highlighted role' do
    let(:role) { Fabricate(:user_role, name: 'Role', highlighted: false) }

    it 'returns empty roles' do
      expect(subject['roles']).to eq []
    end
  end

  context 'when the account is memorialized' do
    before do
      account.memorialize!
    end

    it 'marks it as such' do
      expect(subject['memorial']).to be true
    end
  end

  context 'when created_at is populated' do
    before do
      account.account_stat.update!(created_at: default_datetime)
    end

    it 'parses as RFC 3339 datetime' do
      expect(subject)
        .to include(
          'created_at' => match_api_datetime_format
        )
    end
  end

  context 'when last_status_at is populated' do
    before do
      account.account_stat.update!(last_status_at: default_datetime)
    end

    it 'is serialized as yyyy-mm-dd' do
      expect(subject['last_status_at']).to eq('2024-11-28')
    end
  end

  describe '#online_status' do
    before do
      allow(Setting).to receive(:[]).and_call_original
      allow(Setting).to receive(:[]).with('online_status_enabled').and_return(true)
      user.settings['show_online_status'] = true
      user.last_active_at = 1.minute.ago
    end

    it 'returns the status to an authenticated viewer' do
      expect(subject['online_status']).to eq('online')
    end

    context 'when the viewer is anonymous' do
      let(:current_user) { nil }

      it 'does not expose the status in a public cacheable response' do
        expect(subject['online_status']).to eq('unknown')
      end
    end

    context 'when the server feature is disabled' do
      before { allow(Setting).to receive(:[]).with('online_status_enabled').and_return(false) }

      it 'does not expose the status' do
        expect(subject['online_status']).to eq('unknown')
      end
    end

    context 'when the user does not share their status' do
      before { user.settings['show_online_status'] = false }

      it 'does not expose the status' do
        expect(subject['online_status']).to eq('unknown')
      end
    end

    context 'when the account is remote' do
      let(:account) { Fabricate(:account, domain: 'remote.example') }

      it 'does not expose the status' do
        expect(subject['online_status']).to eq('unknown')
      end
    end
  end

  describe '#pages_view' do
    it 'serializes the local account owner preference' do
      user.settings['web.pages_view'] = 'blog'
      user.settings['web.pages_blog_list_position'] = 'right'

      expect(subject['pages_view']).to eq('blog')
      expect(subject['pages_blog_list_position']).to eq('right')
    end

    context 'when the account is remote' do
      let(:account) { Fabricate(:account, domain: 'remote.example') }

      it 'does not serialize a local-only Pages preference' do
        expect(subject).to_not have_key('pages_view')
      end
    end
  end

  describe 'Sharlayan profile extensions' do
    before do
      allow(Setting).to receive(:[]).and_call_original
      allow(Setting).to receive(:[]).with('avatar_decorations_enabled').and_return(true)
      allow(Setting).to receive(:[]).with('instance_metadata_enabled').and_return(true)
    end

    it 'filters avatar decorations from blocked domains' do
      decoration = Fabricate(:avatar_decoration)
      decoration.update_columns(host: 'blocked.example', remote_id: 'blocked', image_remote_url: 'https://blocked.example/deco.png')
      Fabricate(:avatar_decoration_domain_block, domain: 'blocked.example')
      account.update!(avatar_decorations: [{ 'id' => decoration.id }])

      expect(subject['avatar_decorations']).to be_empty
    end

    context 'with a remote MFM profile' do
      let(:account) { Fabricate(:account, domain: 'misskey.example', mfm: true) }

      it 'exposes the MFM flag only for a compatible server' do
        Fabricate(:instance_metadata, domain: account.domain, software: 'misskey')
        account.update_column(:mfm, true)
        RequestStore.store.delete(:instance_metadata_by_domain)

        expect(subject['mfm']).to be true
      end

      it 'does not expose the MFM flag for an incompatible server' do
        Fabricate(:instance_metadata, domain: account.domain, software: 'mastodon')
        account.update_column(:mfm, true)
        RequestStore.store.delete(:instance_metadata_by_domain)

        expect(subject).to_not have_key('mfm')
      end
    end
  end

  describe '#feature_approval' do
    context 'when account is local' do
      context 'when account is discoverable' do
        it 'includes a policy that allows featuring' do
          expect(subject['feature_approval']).to include({
            'automatic' => ['public'],
            'manual' => [],
            'current_user' => 'automatic',
          })
        end

        context 'when account is locked' do
          let(:account) { Fabricate(:account, locked: true) }

          context 'when the current account does not follow the user' do
            it 'includes a policy that allows featuring for followers and has "denied" for the current user' do
              expect(subject['feature_approval']).to include({
                'automatic' => ['followers'],
                'manual' => [],
                'current_user' => 'denied',
              })
            end
          end

          context 'when the current account follows the user' do
            before { current_user.account.follow!(account) }

            it 'includes a policy that allows featuring for followers and has "automatic" for the current user' do
              expect(subject['feature_approval']).to include({
                'automatic' => ['followers'],
                'manual' => [],
                'current_user' => 'automatic',
              })
            end
          end
        end
      end

      context 'when account is not discoverable' do
        let(:account) { Fabricate(:account, discoverable: false) }

        it 'includes a policy that disallows featuring' do
          expect(subject['feature_approval']).to include({
            'automatic' => [],
            'manual' => [],
            'current_user' => 'denied',
          })
        end
      end
    end

    context 'when account is remote' do
      let(:account) { Fabricate(:account, domain: 'example.com', feature_approval_policy: 0b11000000000000000010) }

      it 'includes the matching policy' do
        expect(subject['feature_approval']).to include({
          'automatic' => ['followers', 'following'],
          'manual' => ['public'],
          'current_user' => 'manual',
        })
      end
    end
  end
end
