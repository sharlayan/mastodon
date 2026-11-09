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

      it 'renders translated decoration, domain block, announcement, drive file and account logs with their targets' do
        logs = crud_actions.map { |action| [render_log(action, decoration), 'sparkle_ring'] } +
               block_actions.map { |action| [render_log(action, domain_block), 'blocked.example'] } +
               crud_actions.map { |action| [render_log(action, announcement), 'Maintenance window'] } +
               [[render_log(:destroy, drive_file), 'attachment.jpg'], [render_log(:update, target_account), 'decorated']]

        logs.each do |html, label|
          expect(html).to_not include('translation_missing')
          expect(html).to include(label)
        end
      end
    end
  end
end
