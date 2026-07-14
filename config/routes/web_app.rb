# frozen_string_literal: true

# Paths handled by the React application, which do not:
# - Require indexing
# - Have alternative format representations

%w(
  /antennas/(*any)
  /blocks
  /board_announcements
  /bookmarks
  /circles/(*any)
  /clips/(*any)
  /collections/(*any)
  /conversations/(*any)
  /custom_emoji_mutes
  /deck/(*any)
  /directory
  /domain_blocks
  /drive
  /explore/(*any)
  /favourites
  /reactions
  /follow_requests
  /followed_tags
  /getting-started
  /getting-started-misc
  /home
  /keyboard-shortcuts
  /links/(*any)
  /lists/(*any)
  /mutes
  /notifications_v2/(*any)
  /notifications/(*any)
  /pinned
  /reaction_mutes
  /profile/(*any)
  /public
  /public/local
  /public/remote
  /publish
  /search
  /start/(*any)
  /statuses/(*any)
  /overview
  /overview/about
).each { |path| get path, to: 'home#index' }
