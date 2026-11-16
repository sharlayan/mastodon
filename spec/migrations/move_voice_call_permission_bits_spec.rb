# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db', 'migrate', '20261111141500_move_voice_call_permission_bits.rb')

RSpec.describe MoveVoiceCallPermissionBits do
  let!(:join_only) { Fabricate(:user_role, extra_permissions: (1 << 1) | (1 << 2)) }
  let!(:share_only) { Fabricate(:user_role, extra_permissions: 1 << 3) }
  let!(:untouched) { Fabricate(:user_role, extra_permissions: 1 << 0) }

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  it 'moves the previously granted voice call bits only where the previous grant ran' do
    ActiveRecord::Base.connection.execute("DELETE FROM schema_migrations WHERE version = '#{described_class::PREVIOUS_GRANT_VERSION}'")
    migrate(:up)
    expect([join_only, share_only, untouched].map { |role| role.reload.extra_permissions }).to eq([(1 << 1) | (1 << 2), 1 << 3, 1 << 0])

    ActiveRecord::Base.connection.execute("INSERT INTO schema_migrations (version) VALUES ('#{described_class::PREVIOUS_GRANT_VERSION}')")
    migrate(:up)
    expect([join_only, share_only, untouched].map { |role| role.reload.extra_permissions }).to eq([(1 << 1) | (1 << 8), 1 << 9, 1 << 0])
    expect(join_only.can_extra?(:join_voice_calls, :view_admin_timeline)).to be true

    migrate(:down)
    expect([join_only, share_only, untouched].map { |role| role.reload.extra_permissions }).to eq([(1 << 1) | (1 << 2), 1 << 3, 1 << 0])
  end
end
