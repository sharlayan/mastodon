# frozen_string_literal: true

class Api::MisskeyCompat::AdminReportsController < Api::MisskeyCompat::BaseController
  include Api::MisskeyCompat::AdminModerationAccess
  include Payloadable

  ORIGINS = %w(combined local remote).freeze
  NOT_FOUND_IDS = {
    'resolve' => 'ac3794dd-2ce4-d878-e546-73c60c06b398',
    'update' => '15f51cf5-46d1-4b1d-a618-b35bcbed0662',
    'forward' => '8763e21b-d9bc-40be-acf6-54c1a6986493',
  }.freeze

  misskey_admin_endpoint 'read:admin:abuse-user-reports', :index, area: 'reports'
  misskey_admin_endpoint 'write:admin:resolve-abuse-user-report', :resolve, :update, :forward, area: 'reports'

  before_action :set_report, except: :index

  def index
    authorize :report, :index?
    return unless valid_origin?(:reporterOrigin) && valid_origin?(:targetUserOrigin)

    reports = paginated_reports.includes(:account, :target_account, :assigned_account, :action_taken_by_account).to_a
    render json: serialize_reports(reports)
  end

  def resolve
    authorize @report, :update?
    resolved_as = params[:resolvedAs].presence
    return render_invalid_param('#/properties/resolvedAs', 'must be equal to one of the allowed values') unless resolved_as.nil? || MisskeyAbuseReportResolution::RESOLUTIONS.include?(resolved_as)

    ApplicationRecord.transaction do
      @report.resolve!(current_account)
      MisskeyAbuseReportResolution.record!(@report, resolved_as)
    end
    log_action :resolve, @report
    head 204
  end

  def update
    authorize @report, :update?
    note = params[:moderationNote]
    return render_invalid_param('#/properties/moderationNote', 'must be string') unless note.nil? || note.is_a?(String)

    if note.present? && note != latest_note_content(@report)
      authorize :report_note, :create?
      current_account.report_notes.create!(report: @report, content: note)
    end
    head 204
  end

  def forward
    authorize @report, :update?
    return render_misskey_internal_error('The target user host is null') if @report.target_account.local?
    return render_misskey_internal_error('The report has already been forwarded') if @report.forwarded?

    @report.update!(forwarded: true)
    representative = Account.representative
    ActivityPub::DeliveryWorker.perform_async(serialize_payload(@report, ActivityPub::FlagSerializer, account: representative).to_json, representative.id, @report.target_account.inbox_url)
    log_action :update, @report
    head 204
  end

  private

  def set_report
    @report = Report.find_by(id: params[:reportId])
    render_error('No such abuse report', 'NO_SUCH_ABUSE_REPORT', 404, id: NOT_FOUND_IDS[action_name], kind: 'server') if @report.nil?
  end

  def valid_origin?(key)
    return true if params[key].nil? || ORIGINS.include?(params[key])

    render_invalid_param("#/properties/#{key}", 'must be equal to one of the allowed values')
    false
  end

  def paginated_reports
    scope = Report.all
    scope = scope.resolved if params[:state] == 'resolved'
    scope = scope.unresolved if params[:state] == 'unresolved'
    scope = apply_origin(scope, :account_id, params[:reporterOrigin])
    scope = apply_origin(scope, :target_account_id, params[:targetUserOrigin])
    scope = apply_compat_pagination_dates(scope)
    scope = scope.where(id: ...params[:untilId].to_i) if params[:untilId].present?
    scope = scope.where(Report.arel_table[:id].gt(params[:sinceId].to_i)) if params[:sinceId].present?
    scope.order(id: forward_pagination? ? :asc : :desc).limit(pagination_limit(default: 10, max: 100))
  end

  def apply_origin(scope, column, origin)
    case origin
    when 'local'
      scope.where(column => Account.local.select(:id))
    when 'remote'
      scope.where(column => Account.remote.select(:id))
    else
      scope
    end
  end

  def latest_note_content(report)
    report.notes.reorder(id: :desc).pick(:content).to_s
  end

  def serialize_reports(reports)
    report_ids = reports.map(&:id)
    resolutions = MisskeyAbuseReportResolution.where(report_id: report_ids).pluck(:report_id, :resolved_as).to_h
    notes = ReportNote.where(report_id: report_ids).reorder(id: :desc).pluck(:report_id, :content).reverse.to_h
    users = misskey_detailed_users(reports.flat_map { |report| [report.account, report.target_account, report_assignee(report)] })

    reports.map do |report|
      assignee = report_assignee(report)

      {
        id: MisskeyCompat::MiId.encode(report.id),
        createdAt: report.created_at.iso8601,
        comment: report.comment,
        resolved: report.action_taken?,
        reporterId: MisskeyCompat::MiId.encode(report.account_id),
        targetUserId: MisskeyCompat::MiId.encode(report.target_account_id),
        assigneeId: assignee && MisskeyCompat::MiId.encode(assignee.id),
        reporter: users[report.account_id],
        targetUser: users[report.target_account_id],
        assignee: assignee && users[assignee.id],
        forwarded: report.forwarded? || false,
        resolvedAs: report.action_taken? ? resolutions[report.id] : nil,
        moderationNote: notes[report.id].to_s,
      }
    end
  end

  def report_assignee(report)
    report.action_taken_by_account || report.assigned_account
  end
end
