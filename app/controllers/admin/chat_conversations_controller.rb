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
      @messages = @conversation.messages.includes(:account, :media_attachments, reactions: :account).page(params[:page]).per(50)
    end

    def destroy
      authorize @conversation, :destroy?
      @conversation.destroy!
      flash[:notice] = I18n.t('generic.changes_saved_msg')
      redirect_to admin_chat_conversations_path
    end

    private

    def set_conversation
      @conversation = ChatConversation.includes(:accounts, :memberships).find(params[:id])
    end

    def filtered_conversations
      scope = ChatConversation.includes(:accounts, :memberships, last_message: :account).order(last_message_id: :desc, id: :desc)
      scope = scope.where(conversation_type: params[:type]) if ChatConversation.conversation_types.key?(params[:type])
      scope = scope.for_account(Account.find(params[:account_id])) if params[:account_id].present?
      scope
    end
  end
end
