# frozen_string_literal: true

class Api::MisskeyCompat::FederationController < Api::MisskeyCompat::BaseController
  SORT_COLUMNS = {
    '+notes' => { notes_count: :desc },
    '-notes' => { notes_count: :asc },
    '+users' => { users_count: :desc },
    '-users' => { users_count: :asc },
    '+following' => { following_count: :desc },
    '-following' => { following_count: :asc },
    '+followers' => { followers_count: :desc },
    '-followers' => { followers_count: :asc },
    '+pubSub' => { following_count: :desc, followers_count: :desc },
    '-pubSub' => { following_count: :asc, followers_count: :asc },
    '+firstRetrievedAt' => { first_retrieved_at: :desc },
    '-firstRetrievedAt' => { first_retrieved_at: :asc },
  }.freeze

  def instances
    return unless object_body!
    return if rate_limited?(:misskey_compat_api)

    stats = filtered_instances.order(sort_order).limit(instances_limit).offset(instances_offset).to_a
    render json: serialize_instances(stats)
  end

  def show_instance
    return unless object_body!
    return if rate_limited?(:misskey_compat_api)

    host = host_param
    return render_invalid_param('#/properties/host', 'must be a non-empty string') if host.blank?

    stat = MisskeyFederationInstanceStat.find_by(domain: host)
    render json: stat ? serialize_instances([stat]).first : nil
  end

  def stats
    return unless object_body!
    return if rate_limited?(:misskey_compat_api)

    limit = pagination_limit(default: 10, max: 100)
    top_sub = MisskeyFederationInstanceStat.where('followers_count > 0').order(followers_count: :desc).limit(limit).to_a
    top_pub = MisskeyFederationInstanceStat.where('following_count > 0').order(following_count: :desc).limit(limit).to_a

    all_sub = MisskeyFederationInstanceStat.sum(:followers_count)
    all_pub = MisskeyFederationInstanceStat.sum(:following_count)
    got_sub = top_sub.sum(&:followers_count)
    got_pub = top_pub.sum(&:following_count)

    serialized = serialize_instances(top_sub + top_pub)
    by_domain = (top_sub + top_pub).zip(serialized).to_h { |stat, json| [stat.domain, json] }

    render json: {
      topSubInstances: top_sub.map { |stat| by_domain[stat.domain] },
      otherFollowersCount: [0, all_sub - got_sub].max,
      topPubInstances: top_pub.map { |stat| by_domain[stat.domain] },
      otherFollowingCount: [0, all_pub - got_pub].max,
    }
  end

  def users
    return unless object_body!
    return if rate_limited?(:misskey_compat_api)

    host = host_param
    return render_invalid_param('#/properties/host', 'must be a non-empty string') if host.blank?

    accounts = paginate_by_id(Account.where(domain: host).includes(:account_stat))
    render json: accounts.map { |account| MisskeyCompat::UserSerializer.serialize(account, detailed: true) }
  end

  def followers
    render_followings(:followers)
  end

  def following
    render_followings(:following)
  end

  def update_remote_user
    return if rate_limited?(:misskey_compat_api)

    require_user!
    return if performed?

    unless current_user.can?(:manage_federation)
      render_error('Insufficient privileges', 'PERMISSION_DENIED', 403)
      return
    end

    account = Account.remote.find_by(id: params[:userId])
    return render_error('No such user', 'NO_SUCH_USER', 404) if account.nil?

    RemoteAccountRefreshWorker.perform_async(account.id)
    head 204
  end

  private

  def render_followings(direction)
    return unless object_body!
    return if rate_limited?(:misskey_compat_api)

    host = host_param
    return render_invalid_param('#/properties/host', 'must be a non-empty string') if host.blank?

    account_ids = Account.where(domain: host).select(:id)
    scope = if direction == :followers
              Follow.where(target_account_id: account_ids)
            else
              Follow.where(account_id: account_ids)
            end

    follows = paginate_by_id(scope.includes(:account, :target_account))
    render json: follows.map { |follow| serialize_following(follow) }
  end

  def serialize_following(follow)
    {
      id: MisskeyCompat::MiId.encode(follow.id),
      createdAt: follow.created_at.iso8601,
      followeeId: MisskeyCompat::MiId.encode(follow.target_account_id),
      followerId: MisskeyCompat::MiId.encode(follow.account_id),
      followee: MisskeyCompat::UserSerializer.serialize(follow.target_account),
      follower: MisskeyCompat::UserSerializer.serialize(follow.account),
    }
  end

  def paginate_by_id(scope)
    scope = scope.where(id: ...params[:untilId].to_i) if params[:untilId].present?
    scope = scope.where('id > ?', params[:sinceId].to_i) if params[:sinceId].present?
    scope.order(id: :desc).limit(pagination_limit(default: 10, max: 100))
  end

  def filtered_instances
    scope = MisskeyFederationInstanceStat.all
    scope = scope.where('domain ILIKE ?', "%#{MisskeyFederationInstanceStat.sanitize_sql_like(host_param.downcase)}%") if host_param.present?
    scope = apply_domain_set_filter(scope, suspended_domains, params[:blocked]) unless params[:blocked].nil?
    scope = apply_domain_set_filter(scope, suspended_domains, params[:suspended]) unless params[:suspended].nil?
    scope = apply_domain_set_filter(scope, silenced_domains, params[:silenced]) unless params[:silenced].nil?
    scope = apply_domain_set_filter(scope, unavailable_domains, params[:notResponding]) unless params[:notResponding].nil?
    scope = apply_federating_filter(scope) unless params[:federating].nil?
    scope = apply_count_filter(scope, :followers_count, params[:subscribing]) unless params[:subscribing].nil?
    scope = apply_count_filter(scope, :following_count, params[:publishing]) unless params[:publishing].nil?
    scope
  end

  def apply_domain_set_filter(scope, domains, flag)
    truthy?(flag) ? scope.where(domain: domains) : scope.where.not(domain: domains)
  end

  def apply_federating_filter(scope)
    if truthy?(params[:federating])
      scope.where('following_count > 0 OR followers_count > 0')
    else
      scope.where(following_count: 0, followers_count: 0)
    end
  end

  def apply_count_filter(scope, column, flag)
    truthy?(flag) ? scope.where("#{column} > 0") : scope.where(column => 0)
  end

  def sort_order
    SORT_COLUMNS.fetch(params[:sort].to_s, { id: :desc })
  end

  def instances_limit
    pagination_limit(default: 30, max: 100)
  end

  def instances_offset
    [params[:offset].to_i, 0].max
  end

  def host_param
    params[:host].to_s.strip.downcase.presence
  end

  def serialize_instances(stats)
    context = MisskeyCompat::FederationInstanceSerializer.build_context(stats.map(&:domain))
    stats.map { |stat| MisskeyCompat::FederationInstanceSerializer.serialize(stat, context: context) }
  end

  def truthy?(value)
    ActiveModel::Type::Boolean.new.cast(value)
  end

  def suspended_domains
    @suspended_domains ||= DomainBlock.where(severity: :suspend).pluck(:domain)
  end

  def silenced_domains
    @silenced_domains ||= DomainBlock.where(severity: :silence).pluck(:domain)
  end

  def unavailable_domains
    @unavailable_domains ||= UnavailableDomain.pluck(:domain)
  end
end
