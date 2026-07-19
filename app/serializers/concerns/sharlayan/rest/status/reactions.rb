# frozen_string_literal: true

module Sharlayan::REST::Status::Reactions
  extend ActiveSupport::Concern

  included do
    attribute :reactions_count
    attribute :reacted, if: :current_user?
    has_many :reactions, serializer: ::REST::ReactionSerializer
  end

  def reactions_count
    relationships&.attributes_map&.dig(object.id, :reactions_count) || object.reactions_count
  end

  def reacted
    if relationships
      relationships.reactions_map[object.proper.id] || false
    else
      current_user.account.reacted?(object)
    end
  end

  def reactions
    if relationships
      relationships.reaction_groups_map[object.proper.id] || []
    else
      object.proper.reactions(current_user&.account&.id)
    end
  end
end
