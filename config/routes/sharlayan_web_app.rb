# frozen_string_literal: true

%w(
  /antennas/(*any)
  /board_announcements
  /circles/(*any)
  /clips/(*any)
  /conversations/(*any)
  /custom_emoji_mutes
  /domain_mutes
  /drive
  /drafts
  /federation/universe
  /pages/(*any)
  /reaction_mutes
  /reactions
  /scheduled
  /timelines/scheduled
).each { |path| get path, to: 'home#index' }
