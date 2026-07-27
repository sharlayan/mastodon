# frozen_string_literal: true

namespace :sharlayan do
  namespace :board_announcements do
    # DESTRUCTIVE: overwrites the cached text_html of every board announcement. Re-runnable, the markdown source is untouched.
    # 파괴적: 모든 게시판 공지의 text_html 캐시를 덮어씁니다. 마크다운 원문은 그대로이므로 다시 실행할 수 있습니다.
    desc 'Re-render board announcement bodies with the current markdown renderer'
    task rerender: :environment do
      count = 0

      BoardAnnouncement.find_each do |announcement|
        announcement.update_column(:text_html, BoardAnnouncementFormatter.new(announcement.text).to_html)
        count += 1
      end

      puts "Re-rendered #{count} board announcements"
    end
  end
end
