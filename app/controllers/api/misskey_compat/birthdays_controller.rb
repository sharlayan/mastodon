# frozen_string_literal: true

class Api::MisskeyCompat::BirthdaysController < Api::MisskeyCompat::BaseController
  BIRTHDAY_PATTERN = '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
  BIRTHDAY_DATE_SQL = '(substring(accounts.birthday from 6 for 2) || substring(accounts.birthday from 9 for 2))::integer'

  requires_misskey_permission 'read:account', :index

  before_action :require_user!

  def index
    range = birthday_range
    return render_invalid_param('#/properties/birthday', 'must be a month/day or begin/end range') if range.nil?

    offset = offset_param(max: MAX_COMPAT_ID)
    return if offset.nil?

    rows = following_with_birthday(range).offset(offset).limit(pagination_limit(default: 10, max: 100)).pluck(:id, Arel.sql(BIRTHDAY_DATE_SQL))
    accounts = Account.where(id: rows.map(&:first)).index_by(&:id)
    context = MisskeyCompat::SerializationContext.new(current_account: current_account)

    render json: rows.filter_map { |id, date| birthday_entry(accounts[id], date, context) }
  end

  private

  def following_with_birthday(range)
    scope = Account.without_suspended.without_requested_deletion
      .joins(:passive_relationships).where(follows: { account_id: current_account.id })
      .where('accounts.birthday ~ ?', BIRTHDAY_PATTERN)
    date = Arel.sql(BIRTHDAY_DATE_SQL)
    scope = scope.where(range.first <= range.last ? date.between(range.first..range.last) : date.between(range.first..1231).or(date.between(101..range.last)))
    scope.reorder(date.asc)
  end

  def birthday_range
    value = params[:birthday]
    return unless value.respond_to?(:key?)

    if value.key?(:begin) && value.key?(:end)
      first = month_day(value[:begin])
      last = month_day(value[:end])
      [first, last] if first && last
    else
      date = month_day(value)
      [date, date] if date
    end
  end

  def month_day(value)
    return unless value.respond_to?(:key?)

    month = value[:month]
    day = value[:day]
    return unless month.is_a?(Integer) && day.is_a?(Integer) && month.between?(1, 12) && day.between?(1, 31)

    (month * 100) + day
  end

  def birthday_entry(account, date, context)
    return if account.nil?

    {
      id: MisskeyCompat::MiId.encode(account.id),
      birthday: next_birthday(date).iso8601,
      user: context.user(account),
    }
  end

  def next_birthday(date)
    today = Time.zone.today
    birthday = Date.new(today.year, date / 100, 1) + ((date % 100) - 1)
    birthday < today ? Date.new(today.year + 1, birthday.month, 1) + (birthday.day - 1) : birthday
  end
end
