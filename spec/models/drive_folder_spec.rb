# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

RSpec.describe DriveFolder do
  let(:account) { Fabricate(:account) }

  describe 'parent ownership' do
    it 'rejects a parent owned by another account' do
      parent = described_class.create!(account: Fabricate(:account), name: 'Foreign')
      folder = described_class.new(account: account, name: 'Local', parent: parent)

      expect(folder).to_not be_valid
      expect(folder.errors.of_kind?(:parent_id, :invalid)).to be true
    end
  end

  describe 'folder hierarchy' do
    it 'rejects moving a folder below its descendant' do
      root = described_class.create!(account: account, name: 'Root')
      child = described_class.create!(account: account, name: 'Child', parent: root)
      grandchild = described_class.create!(account: account, name: 'Grandchild', parent: child)

      root.parent = grandchild

      expect(root).to_not be_valid
      expect(root.errors.of_kind?(:parent_id, :invalid)).to be true
    end

    it 'rejects a parent whose existing ancestry already contains a cycle' do
      first = described_class.create!(account: account, name: 'First')
      second = described_class.create!(account: account, name: 'Second', parent: first)
      first.update_column(:parent_id, second.id)
      folder = described_class.new(account: account, name: 'New child', parent: first)

      Timeout.timeout(2) do
        expect(folder).to_not be_valid
      end

      expect(folder.errors.of_kind?(:parent_id, :invalid)).to be true
    end

    it 'checks the current ancestry instead of a cached parent association' do
      first = described_class.create!(account: account, name: 'First')
      second = described_class.create!(account: account, name: 'Second')
      first.parent = second
      second.parent
      described_class.find(second.id).update!(parent_id: first.id)

      expect(first).to_not be_valid
      expect(first.errors.of_kind?(:parent_id, :invalid)).to be true
    end
  end

  describe 'parent association' do
    it 'keeps the parent instance assigned by the caller through validation' do
      parent = described_class.create!(account: account, name: 'Parent')
      folder = described_class.new(account: account, name: 'Child')
      folder.parent = parent

      expect(folder).to be_valid
      expect(folder.parent).to equal(parent)
    end
  end

  describe 'validation boundaries' do
    it 'reports a missing account as a validation error' do
      folder = described_class.new(name: 'Root')

      expect(folder).to_not be_valid
      expect(folder.errors[:account]).to be_present
    end

    it 'does not try to lock the unsaved changes on the associated account instance' do
      folder = described_class.create!(account: account, name: 'Root')
      account.display_name = 'Unsaved account name'

      expect(folder).to be_valid
      expect(account).to be_changed
      expect(Account.find(account.id).display_name).to_not eq('Unsaved account name')
    end
  end

  describe 'account isolation', use_transactional_tests: false do
    let(:other_account) { Fabricate(:account) }
    let(:other_folder) { described_class.create!(account: other_account, name: 'Other root') }

    after do
      account.destroy!
      other_account.destroy!
    end

    it 'does not wait for the account lock when the parent is unchanged' do
      folder = described_class.create!(account: account, name: 'Root')
      thread = nil

      account.with_lock do
        thread = Thread.new do
          ApplicationRecord.connection_pool.with_connection do
            described_class.find(folder.id).update(name: 'Renamed')
          end
        end

        expect(Timeout.timeout(2) { thread.value }).to be true
      end

      expect(folder.reload.name).to eq('Renamed')
    ensure
      thread&.join
    end

    it 'does not block another account while the first account is locked' do
      other_folder
      thread = nil

      account.with_lock do
        thread = Thread.new do
          ApplicationRecord.connection_pool.with_connection do
            described_class.find(other_folder.id).update(name: 'Renamed')
          end
        end

        expect(Timeout.timeout(2) { thread.value }).to be true
      end

      expect(other_folder.reload.name).to eq('Renamed')
    ensure
      thread&.join
    end
  end

  describe 'concurrent parent moves', use_transactional_tests: false do
    let(:first_folder) { described_class.create!(account: account, name: 'First') }
    let(:second_folder) { described_class.create!(account: account, name: 'Second') }
    let(:first_validated) { Queue.new }
    let(:release_first) { Queue.new }
    let(:second_connection_ids) { Queue.new }
    let(:second_finished) { Queue.new }
    let(:move_threads) { [] }
    let(:pause_first_move) do
      first_id = first_folder.id
      second_id = second_folder.id
      validated = first_validated
      release = release_first
      proc do |folder|
        if folder.id == first_id && folder.parent_id == second_id
          validated << true
          release.pop
        end
      end
    end

    before do
      first_folder
      second_folder
      described_class.set_callback(:validation, :after, pause_first_move)
    end

    after do
      release_first << true
      move_threads.each(&:join)
      described_class.skip_callback(:validation, :after, pause_first_move)
      described_class.where(account: account).update_all(parent_id: nil)
      account.destroy!
    end

    it 'allows only one of two reciprocal parent moves to succeed' do
      first_thread = move_first_folder
      Timeout.timeout(5) { first_validated.pop }
      second_thread = move_second_folder
      pid = Timeout.timeout(5) { second_connection_ids.pop }
      wait_for_second_write(pid)
      release_first << true

      expect([first_thread.value, second_thread.value]).to contain_exactly(true, false)
      expect([first_folder.reload.parent_id, second_folder.reload.parent_id].compact.size).to eq(1)
    end

    def move_first_folder
      move_threads << Thread.new do
        ApplicationRecord.connection_pool.with_connection do
          described_class.find(first_folder.id).update(parent_id: second_folder.id)
        end
      end
      move_threads.last
    end

    def move_second_folder
      move_threads << Thread.new do
        ApplicationRecord.connection_pool.with_connection do |connection|
          second_connection_ids << connection.select_value('SELECT pg_backend_pid()')
          result = described_class.find(second_folder.id).update(parent_id: first_folder.id)
          second_finished << true
          result
        end
      end
      move_threads.last
    end

    def wait_for_second_write(pid)
      Timeout.timeout(5) do
        loop do
          break unless second_finished.empty?
          break if ApplicationRecord.connection.select_value("SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{pid.to_i}") == 'Lock'

          sleep 0.01
        end
      end
    end
  end
end
