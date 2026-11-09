# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'admin/action_logs/_action_log.html.haml' do
  let(:crud_actions) { %i(create update destroy) }
  let(:block_actions) { %i(create destroy) }

  let(:admin) { Fabricate(:admin_user).account }
  let(:target_account) { Fabricate(:account, username: 'decorated') }
  let(:decoration) { Fabricate(:avatar_decoration, name: 'sparkle_ring') }
  let(:domain_block) { AvatarDecorationDomainBlock.create!(domain: 'blocked.example') }
  let(:announcement) { BoardAnnouncement.create!(title: 'Maintenance window', text: 'Body', account: admin) }
  let(:drive_file) { DriveFile.create!(account: target_account, file: attachment_fixture('attachment.jpg')) }

  def render_log(action, target)
    log = Fabricate(:action_log, account: admin, action: action, target: target)
    render partial: 'admin/action_logs/action_log', locals: { action_log: log }
    rendered
  end

  %w(en ko ja).each do |locale|
    context "with the #{locale} locale" do
      around { |example| I18n.with_locale(locale) { example.run } }

      it 'renders avatar decoration logs with their names' do
        crud_actions.each do |action|
          html = render_log(action, decoration)
          expect(html).to_not include('translation_missing')
          expect(html).to include('sparkle_ring')
        end
      end

      it 'renders avatar decoration domain block logs with their domains' do
        block_actions.each do |action|
          html = render_log(action, domain_block)
          expect(html).to_not include('translation_missing')
          expect(html).to include('blocked.example')
        end
      end

      it 'renders board announcement logs with their titles' do
        crud_actions.each do |action|
          html = render_log(action, announcement)
          expect(html).to_not include('translation_missing')
          expect(html).to include('Maintenance window')
        end
      end

      it 'renders drive file deletion logs with the file name' do
        html = render_log(:destroy, drive_file)
        expect(html).to_not include('translation_missing')
        expect(html).to include('attachment.jpg')
      end

      it 'renders account update logs with the account' do
        html = render_log(:update, target_account)
        expect(html).to_not include('translation_missing')
        expect(html).to include('decorated')
      end
    end
  end
end
