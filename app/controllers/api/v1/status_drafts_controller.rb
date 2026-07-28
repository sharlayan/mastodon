# frozen_string_literal: true

class Api::V1::StatusDraftsController < Api::BaseController
  before_action -> { doorkeeper_authorize! :read, :'read:statuses' }, only: [:index, :show]
  before_action -> { doorkeeper_authorize! :write, :'write:statuses' }, only: [:create, :update, :destroy]
  before_action :require_user!
  before_action :enforce_status_draft_rate_limit!
  before_action :set_draft, only: [:show, :update, :destroy]

  def index
    drafts = current_account.status_drafts.within_data_limit.includes(:media_attachments)
      .to_a_paginated_by_id(limit_param(StatusDraft::LIST_LIMIT, StatusDraft::LIST_LIMIT), params_slice(:max_id, :since_id, :min_id))
    render json: drafts, each_serializer: REST::StatusDraftSerializer
  end

  def show
    return render_oversized_draft if @draft.data_bytes > StatusDraft::MAX_DATA_BYTES

    render json: @draft, serializer: REST::StatusDraftSerializer
  end

  def create
    draft = current_account.status_drafts.build(data: draft_data)
    save_with_media!(draft)
    render json: draft, serializer: REST::StatusDraftSerializer
  end

  def update
    @draft.data = draft_data
    save_with_media!(@draft)
    render json: @draft, serializer: REST::StatusDraftSerializer
  end

  def destroy
    @draft.destroy!
    render_empty
  end

  private

  def set_draft
    @draft = current_account.status_drafts.find(params[:id])
  end

  def enforce_status_draft_rate_limit!
    RateLimiter.new(current_account, family: :status_drafts).record!
  end

  def render_oversized_draft
    render json: { error: I18n.t('status_drafts.data_too_large', limit: StatusDraft::MAX_DATA_BYTES / 1.kilobyte) }, status: 422
  end

  def draft_data
    params.permit(
      :status, :spoiler_text, :content_type, :local_only, :in_reply_to_id,
      :sensitive, :visibility, :circle_id, :language, :quoted_status_id,
      :quote_approval_policy, :scheduled_at,
      clip_ids: [],
      poll: [:expires_in, :multiple, :hide_totals, { options: [] }]
    ).to_h
  end

  def save_with_media!(draft)
    media_ids = Array(params[:media_ids]).first(Status::MEDIA_ATTACHMENTS_LIMIT).map(&:to_i)

    current_account.with_lock do
      draft.save!
      media = current_account.media_attachments.where(status_id: nil, scheduled_status_id: nil)
        .where(status_draft_id: [nil, draft.id]).where(id: media_ids).index_by(&:id)
      raise ActiveRecord::RecordNotFound unless media_ids.all? { |id| media.key?(id) }

      draft.media_attachments.where.not(id: media_ids).update_all(status_draft_id: nil)
      media_ids.each { |id| media.fetch(id).update!(status_draft: draft) }
    end
  end
end
