# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mastodon::Version do
  let(:version) do
    described_class.dup.tap do |copy|
      copy.instance_variables.each { |name| copy.remove_instance_variable(name) }
    end
  end

  around do |example|
    Dir.mktmpdir('mastodon-version') do |directory|
      Dir.chdir(directory) { example.run }
    end
  end

  it 'boots with the development fallback when .git is a worktree pointer file' do
    File.write('.git', 'gitdir: /repository/.git/worktrees/chat')

    expect(version.read_git_head_file).to eq('')
    expect(version.read_git_hash_from_file).to eq('')
    expect(version.current_git_branch).to eq('dev')
  end

  it 'tolerates a reference whose parent is not a directory' do
    Dir.mkdir('.git')
    File.write('.git/HEAD', "ref: refs/heads/develop\n")
    File.write('.git/refs', 'unavailable')

    expect(version.read_git_hash_from_file).to eq('')
  end

  it 'continues to read the branch and short hash from a regular checkout' do
    FileUtils.mkdir_p('.git/refs/heads')
    File.write('.git/HEAD', "ref: refs/heads/develop\n")
    File.write('.git/refs/heads/develop', "123456789abcdef\n")

    expect(version.read_git_hash_from_file).to eq('12345')
    expect(version.current_git_branch).to eq('develop')
  end

  it 'reads the short hash from packed refs when the loose reference is missing' do
    Dir.mkdir('.git')
    File.write('.git/HEAD', "ref: refs/heads/develop\n")
    File.write('.git/packed-refs', <<~REFS)
      # pack-refs with: peeled fully-peeled sorted
      fedcba987654321 refs/heads/dev
      abcdef123456789 refs/heads/develop
      ^0123456789abcde
    REFS

    expect(version.read_git_hash_from_file).to eq('abcde')
  end
end
