# frozen_string_literal: true

module Sharlayan
  module VoiceCallFederation
    ROOM_PATH = %r{\A/chat/rooms/([0-9]+)\z}
    SIGNAL_PATH = '/livekit'
    STATE_TYPE = 'ChatRoomVoiceState'
    NAMESPACE = 'https://kokonect.link/ns#'
    CONTEXT = [
      'https://www.w3.org/ns/activitystreams',
      {
        'cherrypick' => NAMESPACE,
        'ChatRoomVoiceState' => 'cherrypick:ChatRoomVoiceState',
        'room' => { '@id' => 'cherrypick:room', '@type' => '@id' },
        'participants' => { '@id' => 'cherrypick:participants', '@container' => '@list' },
        'screenSharing' => 'cherrypick:screenSharing',
        'micMuted' => 'cherrypick:micMuted',
        'deafened' => 'cherrypick:deafened',
      },
    ].freeze

    module_function

    def federation_ready?
      Setting.chat_enabled && Sharlayan::ChatFederation.enabled?
    end

    def host_enabled?
      federation_ready? && Sharlayan::VoiceCallService.enabled? && Setting.voice_call_federation_host_enabled
    end

    def remote_join_enabled?
      federation_ready? && Setting.voice_call_remote_join_enabled
    end

    def hosted_room?(conversation)
      conversation.present? && conversation.chat_group? && conversation.owner_account&.local? == true
    end

    def remote_account_permitted?(account)
      host_enabled? && account.present? && !account.local? && !account.unavailable? && !DomainBlock.blocked?(account.domain)
    end

    def local_room_id(uri)
      parsed = Addressable::URI.parse(uri.to_s)
      return if parsed.query || parsed.fragment || parsed.userinfo
      return unless local_origins.include?(parsed.normalized_site)

      ROOM_PATH.match(parsed.path)&.captures&.first
    rescue Addressable::URI::InvalidURIError
      nil
    end

    def local_origins
      web = origin_of("#{Rails.configuration.x.use_https ? 'https' : 'http'}://#{Rails.configuration.x.web_domain}")
      [web, origin_of(ActivityPub::TagManager.instance.root_url)].compact.uniq
    end

    def origin_of(uri)
      parsed = Addressable::URI.parse(uri.to_s)
      return unless %w(http https).include?(parsed.scheme) && parsed.host.present?

      parsed.normalized_site
    rescue Addressable::URI::InvalidURIError
      nil
    end

    def actor_origin(account)
      origin_of(ActivityPub::TagManager.instance.uri_for(account))
    end

    def signal_url_for(account)
      "#{actor_origin(account)}#{SIGNAL_PATH}"
    end

    def state_id(room_uri)
      "#{room_uri}/voice"
    end

    def participant_entries(participants, key: 'id')
      participants.map do |participant|
        { key => participant['identity'], 'screenSharing' => participant['screen_sharing'] == true, 'micMuted' => participant['mic_muted'] == true, 'deafened' => participant['deafened'] == true }
      end
    end
  end
end
