# frozen_string_literal: true

class Web::NotificationSerializer < ActiveModel::Serializer
  include RoutingHelper
  include ActionView::Helpers::TextHelper
  include ActionView::Helpers::SanitizeHelper

  attributes :access_token, :preferred_locale, :notification_id,
             :notification_type, :icon, :title, :body

  private

  def status_plain_text(status)
    if status.local? && status.content_type == 'text/x-mfm'
      MfmHtmlConverter.convert(status.text)
    else
      status.text
    end
  end

  public

  def access_token
    current_push_subscription.associated_access_token
  end

  def preferred_locale
    current_push_subscription.user&.locale || I18n.default_locale
  end

  def notification_id
    object.id
  end

  def notification_type
    object.type
  end

  def icon
    full_asset_url(object.from_account.avatar_static_url)
  end

  def title
    I18n.t("notification_mailer.#{object.type}.subject", name: object.from_account.display_name.presence || object.from_account.username)
  end

  def body
    status = object.target_status
    raw = if status
            status.spoiler_text.presence || status_plain_text(status)
          else
            object.from_account.note
          end
    str = strip_tags(raw)
    truncate(HTMLEntities.new.decode(str.to_str), length: 140, escape: false) # Do not encode entities, since this value will not be used in HTML
  end
end
