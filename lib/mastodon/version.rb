# frozen_string_literal: true

module Mastodon
  module Version
    module_function

    def major
      4
    end

    def minor
      7
    end

    def patch
      0
    end

    def default_prerelease
      'alpha.2'
    end

    def prerelease
      version_configuration[:prerelease].presence || read_git_hash_from_file
    end

    def build_metadata
      version_configuration[:metadata]
    end

    def to_a
      [major, minor, patch].compact
    end

    def to_s
      components = [to_a.join('.')]
      components << "-#{prerelease}" if prerelease.present?
      components << "+#{build_metadata}" if build_metadata.present?
      components.join
    end

    def gem_version
      @gem_version ||= Gem::Version.new(to_s.split('+')[0])
    end

    def api_versions
      {
        mastodon: 11,
        glitch: 1,
      }
    end

    def repository
      source_configuration[:repository] || "sharlayan/mastodon/tree/#{current_git_branch}"
    end

    def source_base_url
      source_configuration[:base_url] || "https://github.com/#{repository}"
    end

    # specify git tag or commit hash here
    def source_tag
      source_configuration[:tag]
    end

    def source_url
      if source_tag
        "#{source_base_url}/tree/#{source_tag}"
      else
        source_base_url
      end
    end

    def source_commit
      ENV.fetch('SOURCE_COMMIT', nil)
    end

    def user_agent
      @user_agent ||= "Mastodon/#{Version} (#{HTTP::Request::USER_AGENT}; +http#{'s' if Rails.configuration.x.use_https}://#{Rails.configuration.x.web_domain}/)"
    end

    def version_configuration
      mastodon_configuration.version
    end

    def source_configuration
      mastodon_configuration.source
    end

    def mastodon_configuration
      Rails.configuration.x.mastodon
    end

    def read_git_head_file
      head_file_path = '.git/HEAD'
      File.read(head_file_path).strip
    rescue Errno::ENOENT, Errno::EACCES, IOError
      ''
    end

    def read_git_hash_from_file
      head_file_content = read_git_head_file
      return '' if head_file_content.empty?

      if head_file_content.start_with?('ref:')
        ref_path = head_file_content.sub('ref: ', '').strip
        ref_file_path = File.join('.git', ref_path)
        ref_file_content = File.read(ref_file_path).strip
        ref_file_content[0, 5]
      else
        head_file_content[0, 5]
      end
    rescue Errno::ENOENT, Errno::EACCES, IOError
      ''
    end

    def current_git_branch
      head_file_content = read_git_head_file
      return 'dev' if head_file_content.empty?

      if head_file_content.start_with?('ref: refs/heads/')
        head_file_content.delete_prefix('ref: refs/heads/')
      else
        'Detached from HEAD'
      end
    end
  end
end
