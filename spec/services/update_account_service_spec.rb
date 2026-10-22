# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UpdateAccountService do
  subject { described_class.new }

  describe 'copying profile images from Drive' do
    let(:account) { Fabricate(:user).account }
    let(:drive_file) { account.drive_files.create!(file: attachment_fixture('attachment.jpg')) }
    let(:params) { { header_drive_file_id: drive_file.id.to_s, display_name: 'Changed' } }
    let(:copy_paths) { [] }

    before do
      Setting.drive_enabled = true
      allow(account.drive_files).to receive(:find).with(drive_file.id.to_s).and_return(drive_file)
    end

    context 'when the storage backend reports a failed download' do
      before do
        allow(drive_file.file).to receive(:copy_to_local_file) do |_, destination|
          copy_paths << destination
          File.write(destination, 'incomplete download')
          false
        end
      end

      it 'rejects the selection and removes the temporary copy' do
        expect { expect(subject.call(account, params)).to be(false) }
          .to not_change { Account.find(account.id).display_name }
          .and(not_change { Account.find(account.id).header_file_name })

        expect(account.errors.of_kind?(:header, :invalid)).to be(true)
        expect(File).to_not exist(copy_paths.fetch(0))
        expect(drive_file.reload.file).to exist
      end

      it 'raises a validation error when requested' do
        expect { subject.call(account, params, raise_error: true) }
          .to raise_error(ActiveRecord::RecordInvalid)

        expect(File).to_not exist(copy_paths.fetch(0))
      end
    end

    context 'when copying the original raises an error' do
      before do
        allow(drive_file.file).to receive(:copy_to_local_file) do |_, destination|
          copy_paths << destination
          raise IOError, 'Download interrupted'
        end
      end

      it 'removes the temporary copy before propagating the error' do
        expect { subject.call(account, params) }.to raise_error(IOError, 'Download interrupted')

        expect(File).to_not exist(copy_paths.fetch(0))
      end
    end

    context 'when the storage backend replaces the destination file' do
      before do
        allow(drive_file.file).to receive(:copy_to_local_file) do |_, destination|
          copy_paths << destination
          File.binwrite("#{destination}.download", File.binread(drive_file.file.path))
          File.rename("#{destination}.download", destination)
          true
        end
      end

      it 'saves the downloaded bytes and removes the temporary copy' do
        expect(subject.call(account, params, raise_error: true)).to be(true)

        expect(File.binread(account.reload.header.path)).to eq(File.binread(drive_file.file.path))
        expect(File).to_not exist(copy_paths.fetch(0))
      end
    end
  end

  describe 'updating avatar decorations' do
    let(:account) { Fabricate(:user).account }

    before do
      Setting.avatar_decorations_enabled = true
    end

    context 'when local decorations are enabled' do
      before { Setting.avatar_decorations_local_only_view = false }

      it 'saves an available local decoration selection' do
        decoration = Fabricate(:avatar_decoration, approved: true)

        subject.call(account, { avatar_decorations: [{ id: decoration.id, scale: 1.2 }] })

        expect(account.reload.avatar_decorations).to contain_exactly(include('id' => decoration.id, 'scale' => 1.2))
      end
    end

    context 'when only remote decorations may be viewed' do
      before { Setting.avatar_decorations_local_only_view = true }

      it 'rejects local decoration selections' do
        decoration = Fabricate(:avatar_decoration, approved: true)

        subject.call(account, { avatar_decorations: [{ id: decoration.id }] })

        expect(account.reload.avatar_decorations).to be_empty
      end
    end
  end

  describe 'switching form locked to unlocked accounts', :inline_jobs do
    let(:account) { Fabricate(:account, locked: true) }
    let(:alice)   { Fabricate(:account) }
    let(:bob)     { Fabricate(:account) }
    let(:eve)     { Fabricate(:account) }
    let(:newcomer) { Fabricate(:account) }

    before do
      alice.update_column(:created_at, 8.days.ago)
      eve.update_column(:created_at, 8.days.ago)
      bob.touch(:silenced_at)
      account.mute!(eve)

      FollowService.new.call(alice, account)
      FollowService.new.call(bob, account)
      FollowService.new.call(eve, account)
      FollowService.new.call(newcomer, account)
    end

    it 'auto accepts pending follow requests from appropriate accounts' do
      subject.call(account, { locked: false })

      expect(alice).to be_following(account)
      expect(alice).to_not be_requested(account)

      expect(bob).to_not be_following(account)
      expect(bob).to be_requested(account)

      expect(eve).to be_following(account)
      expect(eve).to_not be_requested(account)

      expect(newcomer).to_not be_following(account)
      expect(newcomer).to be_requested(account)
    end
  end

  describe 'adding domains to attribution_domains' do
    let(:account) { Fabricate(:account) }
    let!(:preview_card) { Fabricate(:preview_card, url: 'https://writer.example.com/article', unverified_author_account: account, author_account: nil) }
    let!(:unattributable_preview_card) { Fabricate(:preview_card, url: 'https://otherwriter.example.com/article', unverified_author_account: account, author_account: nil) }
    let!(:unrelated_preview_card) { Fabricate(:preview_card) }

    it 'reattributes expected preview cards' do
      expect { subject.call(account, { attribution_domains: ['writer.example.com'] }) }
        .to change { preview_card.reload.author_account }.from(nil).to(account)
        .and not_change { unattributable_preview_card.reload.author_account }
        .and(not_change { unrelated_preview_card.reload.author_account })
    end
  end
end
