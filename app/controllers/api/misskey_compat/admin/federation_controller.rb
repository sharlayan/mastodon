# frozen_string_literal: true

class Api::MisskeyCompat::Admin::FederationController < Api::MisskeyCompat::Admin::ServerBaseController
  misskey_admin_endpoint :delete_all_files, :refresh_metadata, :remove_all_following, :update_instance, :update_remote_user, kind: 'write:admin:federation', permission: :manage_federation

  before_action :set_domain, except: :update_remote_user

  def update_remote_user
    return if rate_limited?(:misskey_compat_api)

    account = Account.remote.find_by(id: params[:userId])
    return render_error('No such user', 'NO_SUCH_USER', 404) if account.nil?

    RemoteAccountRefreshWorker.perform_async(account.id)
    head 204
  end

  def delete_all_files
    authorize :instance, :destroy?

    MisskeyCompatRemoteMediaCleanupWorker.perform_async(@domain)
    head 204
  end

  def refresh_metadata
    authorize :instance, :refresh_metadata?
    return render_no_such_instance unless known_instance?

    InstanceMetadataUpdateWorker.perform_async(@domain, 'manual')
    head 204
  end

  def remove_all_following
    authorize :instance, :destroy?

    MisskeyCompatRemoveDomainFollowersWorker.perform_async(@domain)
    head 204
  end

  def update_instance
    return unless require_boolean_param!(:isSuspended)
    return if params.key?(:moderationNote) && !require_string_param!(:moderationNote)
    return render_no_such_instance unless known_instance?

    update_suspension(params[:isSuspended]) unless params[:isSuspended].nil?
    add_moderation_note(params[:moderationNote]) if params[:moderationNote].present?

    head 204
  end

  private

  def set_domain
    return render_invalid_param('#/properties/host', 'must be string') unless params[:host].is_a?(String)

    @domain = TagManager.instance.normalize_domain(params[:host].strip)
    render_invalid_param('#/properties/host', 'must be a remote host') if @domain.blank? || TagManager.instance.local_domain?(@domain)
  rescue Addressable::URI::InvalidURIError, IDN::Idna::IdnaError
    render_invalid_param('#/properties/host', 'must be a valid host')
  end

  def known_instance?
    Instance.exists?(domain: @domain) || MisskeyFederationInstanceStat.exists?(domain: @domain) || Account.remote.exists?(domain: @domain)
  end

  def render_no_such_instance
    render_error('No such instance', 'NO_SUCH_INSTANCE', 404)
  end

  def update_suspension(suspended)
    suspended ? suspend_domain! : unsuspend_domain!
  end

  def suspend_domain!
    existing = DomainBlock.rule_for(@domain)
    return if existing&.suspend?

    # DESTRUCTIVE: Mastodon suspension deletes cached content, media and profiles of the domain's accounts.
    # 파괴적: Mastodon 서버 정지는 해당 도메인 계정의 캐시된 콘텐츠·미디어·프로필을 삭제합니다.
    if existing&.domain == @domain
      authorize existing, :update?
      existing.update!(severity: :suspend)
      DomainBlockWorker.perform_async(existing.id, true)
      log_action :update, existing
    else
      authorize :domain_block, :create?
      block = DomainBlock.create!(domain: @domain, severity: :suspend)
      DomainBlockWorker.perform_async(block.id)
      log_action :create, block
    end
  end

  def unsuspend_domain!
    block = DomainBlock.find_by(domain: @domain, severity: :suspend)
    return if block.nil?

    authorize block, :destroy?
    UnblockDomainService.new.call(block)
    log_action :destroy, block
  end

  def add_moderation_note(content)
    authorize :instance_moderation_note, :create?
    return if InstanceModerationNote.where(domain: @domain).order(id: :desc).pick(:content) == content

    current_account.instance_moderation_notes.create!(domain: @domain, content: content)
  end
end
