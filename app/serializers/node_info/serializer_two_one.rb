# frozen_string_literal: true

class NodeInfo::SerializerTwoOne < ActiveModel::Serializer
  include SharlayanCapabilitiesHelper

  attributes :version, :software, :protocols, :services, :usage, :metadata
  attribute :open_registrations, key: :openRegistrations

  def version
    '2.1'
  end

  def software
    {
      name: 'mastodon',
      version: Mastodon::Version.to_s,
      homepage: Mastodon::Version.source_url,
      repository: Mastodon::Version.source_url,
    }
  end

  def protocols
    %w(activitypub)
  end

  def services
    { inbound: [], outbound: [] }
  end

  def open_registrations
    Setting.registrations_mode != 'none' && !Rails.configuration.x.single_user_mode
  end

  def usage
    {
      users: {
        total: instance_presenter.user_count,
        activeHalfyear: instance_presenter.active_user_count(24),
        activeMonth: instance_presenter.active_user_count(4),
      },
      localPosts: instance_presenter.status_count,
      localComments: 0,
    }
  end

  def metadata
    {
      'nodeName' => Setting.site_title,
      'nodeDescription' => Setting.site_short_description,
      'nodeAdmins' => [maintainer],
      'maintainer' => maintainer,
      'langs' => instance_presenter.languages,
      'tosUrl' => terms_url,
      'privacyPolicyUrl' => privacy_url,
      'inquiryUrl' => instance_url,
      'impressumUrl' => '',
      'repositoryUrl' => Mastodon::Version.source_url,
      'feedbackUrl' => '',
      'disableRegistration' => !open_registrations,
      'disableLocalTimeline' => false,
      'disableGlobalTimeline' => false,
      'emailRequiredForSignup' => false,
      'enableHcaptcha' => false,
      'enableRecaptcha' => false,
      'enableMcaptcha' => false,
      'enableTurnstile' => false,
      'maxNoteTextLength' => StatusLengthValidator.max_chars,
      'enableEmail' => true,
      'enableServiceWorker' => true,
      'proxyAccountName' => '',
      'themeColor' => Setting.theme_color.presence || '#6364ff',
      'features' => capabilities_for_nodeinfo,
      'upstream' => {
        'name' => 'mastodon',
        'version' => Mastodon::Version.to_s,
      },
    }
  end

  private

  def maintainer
    {
      name: Setting.site_contact_username.presence || Setting.site_title,
      email: Setting.site_contact_email.presence || '',
    }
  end

  def terms_url
    TermsOfService.current.present? ? "#{instance_url}/terms-of-service" : ''
  end

  def privacy_url
    "#{instance_url}/privacy-policy"
  end

  def instance_url
    @instance_url ||= "http#{'s' if Rails.configuration.x.use_https}://#{Rails.configuration.x.web_domain}"
  end

  def instance_presenter
    @instance_presenter ||= InstancePresenter.new
  end
end
