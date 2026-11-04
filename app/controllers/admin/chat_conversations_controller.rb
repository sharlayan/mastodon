# frozen_string_literal: true

module Admin
  class ChatConversationsController < BaseController
    before_action :set_conversation, only: [:show, :destroy]

    def index
      authorize :chat_conversation, :index?
      @conversations = filtered_conversations.page(params[:page])
    end

    def show
      authorize @conversation, :show?
      @messages = @conversation.messages.includes(:account, :edits, :media_attachments, reactions: :account).page(params[:page]).per(50)
    end

    def destroy
      authorize @conversation, :destroy?
      Sharlayan::ChatService.new.destroy_conversation_as_admin(@conversation)
      flash[:notice] = I18n.t('generic.changes_saved_msg')
      redirect_to admin_chat_conversations_path
    end

    private

    def require_moderator_or_admin_permissions
      return if RoleplayModeHelper.roleplay_mode? && current_user&.role&.can_extra?(:view_admin_timeline)

      super
    end

    def set_conversation
      @conversation = ChatConversation.includes(:accounts, :memberships).find(params[:id])
    end

    def filtered_conversations
      scope = ChatConversation.local_only.preload(:accounts, :memberships, last_message: :account).order(last_message_id: :desc, id: :desc)
      scope = scope.where(conversation_type: params[:type]) if ChatConversation.conversation_types.key?(params[:type])
      scope = scope.for_account(Account.find(params[:account_id])) if params[:account_id].present?
      scope
    end
  end
end
