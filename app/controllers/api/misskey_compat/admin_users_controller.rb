# frozen_string_literal: true

class Api::MisskeyCompat::AdminUsersController < Api::MisskeyCompat::BaseController
  include Api::MisskeyCompat::AdminModerationAccess

  STATES = %w(all alive available admin moderator adminOrModerator suspended).freeze
  SORTS = %w(+follower -follower +createdAt -createdAt +updatedAt -updatedAt +lastActiveDate -lastActiveDate).freeze
  ORIGINS = %w(combined local remote).freeze
  PROFILE_FIELDS = %i(followedMessage autoAcceptFollowed noCrawle preventAiLearning alwaysMarkNsfw carefulBot mutedWords mutedInstances).freeze
  NO_SUCH_USER_ID = 'ccafc7fe-5074-4edd-9dc0-8ef9ef6a701d'
  SIGNIN_LIMIT = 100
  IP_LIMIT = 30
  GENERATED_PASSWORD_LENGTH = 8

  misskey_admin_endpoint 'read:admin:show-user', :show, :index, area: 'accounts'
  misskey_admin_endpoint 'write:admin:suspend-user', :suspend, area: 'accounts'
  misskey_admin_endpoint 'write:admin:unsuspend-user', :unsuspend, area: 'accounts'
  misskey_admin_endpoint 'write:admin:unset-mfa', :unset_mfa, area: 'accounts'
  misskey_admin_endpoint 'write:admin:unset-user-avatar', :unset_avatar, area: 'accounts'
  misskey_admin_endpoint 'write:admin:unset-user-banner', :unset_banner, area: 'accounts'
  misskey_admin_endpoint 'write:admin:user-note', :update_note, area: 'accounts'
  misskey_admin_endpoint 'write:admin:reset-password', :reset_password, area: 'accounts'
  misskey_admin_endpoint 'read:admin:user-ips', :ips, area: 'accounts', administrator: true
  misskey_admin_endpoint 'write:admin:delete-all-files-of-a-user', :delete_all_files, area: 'accounts', administrator: true
  misskey_admin_endpoint 'read:admin:account', :find_by_email, area: 'accounts', administrator: true

  before_action :set_account, except: [:index, :find_by_email]
  before_action :require_local_user!, only: [:unset_mfa, :reset_password]

  def index
    authorize :account, :index?
    return unless valid_choice?(:state, STATES) && valid_choice?(:sort, SORTS) && valid_choice?(:origin, ORIGINS)

    offset = offset_param
    return if offset.nil?

    accounts = sorted_accounts(filtered_accounts).limit(pagination_limit(default: 10, max: 100)).offset(offset).to_a
    collection = MisskeyCompat::UserCollectionContext.for(accounts, viewer: current_account)
    render json: accounts.map { |account| MisskeyCompat::UserSerializer.serialize(account, detailed: true, viewer: current_account, relationships: collection.relationships, collection:) }
  end

  def show
    authorize @account, :show?
    render json: serialize_admin_user(@account)
  end

  def suspend
    return head 204 if @account.suspended?

    authorize @account, :show?
    action = Admin::AccountAction.new(type: 'suspend', target_account: @account, current_account: current_account)
    action.save!
    head 204
  end

  def unsuspend
    return head 204 unless @account.suspended?

    authorize @account, :unsuspend?
    @account.unsuspend!
    Admin::UnsuspensionWorker.perform_async(@account.id)
    log_action :unsuspend, @account
    head 204
  end

  def unset_mfa
    authorize @user, :disable_2fa?
    @user.disable_two_factor!
    log_action :disable_2fa, @user
    UserMailer.two_factor_disabled(@user).deliver_later!
    head 204
  end

  def unset_avatar
    return head 204 unless @account.avatar.file?

    authorize @account, :remove_avatar?
    @account.avatar = nil
    @account.save!
    log_action :remove_avatar, @account.user
    head 204
  end

  def unset_banner
    return head 204 unless @account.header.file?

    authorize @account, :remove_header?
    @account.header = nil
    @account.save!
    log_action :remove_header, @account.user
    head 204
  end

  def update_note
    authorize AccountModerationNote, :create?
    text = params[:text]
    return render_invalid_param('#/properties/text', 'must be string') unless text.is_a?(String)

    current_account.account_moderation_notes.create!(target_account: @account, content: text) if text.present? && text != latest_moderation_note(@account)
    head 204
  end

  def reset_password
    authorize @user, :reset_password?
    password = SecureRandom.alphanumeric(GENERATED_PASSWORD_LENGTH)
    @user.change_password!(password)
    log_action :reset_password, @user
    render json: { password: password }
  end

  def ips
    authorize @account, :show?
    ips = @account.user.nil? ? [] : @account.user.ips.by_latest_used.limit(IP_LIMIT).to_a
    render json: ips.map { |ip| { ip: ip.ip.to_s, createdAt: ip.used_at&.iso8601 } }
  end

  def delete_all_files
    authorize :drive_file, :destroy?
    @account.drive_files.find_each do |drive_file|
      log_action :destroy, drive_file if drive_file.destroy
    end
    head 204
  end

  def find_by_email
    authorize :account, :index?
    email = params[:email]
    return render_invalid_param('#/properties/email', 'must be string') unless email.is_a?(String)

    user = User.find_by(email: email.strip.downcase)
    return render_error('No such user who has the email address', 'USER_NOT_FOUND', 400, id: 'cb865949-8af5-4062-a88c-ef55e8786d1d') if user.nil?

    render json: MisskeyCompat::UserSerializer.serialize(user.account, detailed: true)
  end

  private

  def set_account
    @account = Account.find(params[:userId])
  end

  def require_local_user!
    @user = @account.user
    render_error('No such user', 'NO_SUCH_USER', 400, id: NO_SUCH_USER_ID) if @user.nil?
  end

  def valid_choice?(key, choices)
    return true if params[key].nil? || choices.include?(params[key])

    render_invalid_param("#/properties/#{key}", 'must be equal to one of the allowed values')
    false
  end

  def filtered_accounts
    scope = apply_user_origin(Account.without_instance_actor.left_joins(:account_stat))
    scope = apply_user_state(scope)
    scope = scope.where('accounts.username ILIKE ?', "#{Account.sanitize_sql_like(params[:username])}%") if params[:username].is_a?(String) && params[:username].present?
    scope = scope.where(domain: params[:hostname].downcase) if params[:hostname].is_a?(String) && params[:hostname].present?
    scope
  end

  def apply_user_state(scope)
    case params[:state]
    when 'available'
      scope.where(suspended_at: nil)
    when 'suspended'
      scope.where.not(suspended_at: nil)
    when 'alive'
      scope.where(account_stats: { last_status_at: 5.days.ago.. })
    when 'admin', 'moderator', 'adminOrModerator'
      scope.joins(:user).where(users: { role_id: staff_role_ids(params[:state]) })
    else
      scope
    end
  end

  def staff_role_ids(state)
    admin_ids = UserRole.where('permissions & ? != 0', UserRole::FLAGS[:administrator]).pluck(:id)
    moderator_ids = UserRole.that_can(*UserRole::Flags::CATEGORIES[:moderation]).map(&:id) - admin_ids

    case state
    when 'admin' then admin_ids
    when 'moderator' then moderator_ids
    else admin_ids + moderator_ids
    end
  end

  def sorted_accounts(scope)
    case params[:sort]
    when nil
      scope.order(accounts: { id: :asc })
    when '+lastActiveDate'
      scope.left_joins(:user).order(Arel.sql('users.last_active_at DESC NULLS LAST'))
    when '-lastActiveDate'
      scope.left_joins(:user).order(Arel.sql('users.last_active_at ASC NULLS FIRST'))
    else
      apply_user_sort(scope)
    end
  end

  def latest_moderation_note(account)
    account.targeted_moderation_notes.reorder(id: :desc).pick(:content).to_s
  end

  def serialize_admin_user(account)
    user = account.user
    role = user&.role
    profile = user ? MisskeyCompat::UserSerializer.serialize(account, detailed: true, me_user: user).slice(*PROFILE_FIELDS) : {}
    assigned_role = role.nil? || role.everyone? ? nil : role

    {
      email: user&.email,
      emailVerified: user&.confirmed? || false,
      followedMessage: profile[:followedMessage],
      autoAcceptFollowed: profile.fetch(:autoAcceptFollowed, false),
      noCrawle: profile.fetch(:noCrawle, false),
      preventAiLearning: profile.fetch(:preventAiLearning, false),
      alwaysMarkNsfw: profile.fetch(:alwaysMarkNsfw, false),
      autoSensitive: false,
      carefulBot: profile.fetch(:carefulBot, false),
      injectFeaturedNote: false,
      receiveAnnouncementEmail: false,
      mutedWords: profile.fetch(:mutedWords, []),
      mutedInstances: profile.fetch(:mutedInstances, []),
      notificationRecieveConfig: {},
      isModerator: role.present? && role.can?(*UserRole::Flags::CATEGORIES[:moderation]),
      isSilenced: account.silenced?,
      isSuspended: account.suspended?,
      isHibernated: false,
      lastActiveDate: (user&.last_active_at || user&.current_sign_in_at)&.iso8601,
      moderationNote: latest_moderation_note(account),
      signins: user ? serialize_signins(user) : [],
      policies: compat_policies,
      roles: assigned_role ? [MisskeyCompat::AdminRoleSerializer.serialize(assigned_role, base_policies: MisskeyCompat::AdminRoleSerializer.base_policies(compat_policies))] : [],
      roleAssigns: assigned_role ? [{ createdAt: role_assigned_at(user).iso8601, expiresAt: nil, roleId: MisskeyCompat::MiId.encode(assigned_role.id) }] : [],
    }
  end

  def serialize_signins(user)
    user.login_activities.order(id: :desc).limit(SIGNIN_LIMIT).map do |activity|
      { id: MisskeyCompat::MiId.encode(activity.id), createdAt: activity.created_at.iso8601, ip: activity.ip.to_s, headers: { 'user-agent' => activity.user_agent.to_s }, success: activity.success? }
    end
  end

  def role_assigned_at(user)
    Admin::ActionLog.where(target: user, action: 'change_role').maximum(:created_at) || user.created_at
  end
end
