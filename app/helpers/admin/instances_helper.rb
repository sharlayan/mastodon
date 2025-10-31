# frozen_string_literal: true

module Admin::InstancesHelper
  def admin_instance_link_to(instance)
    link_to instance.domain, admin_instance_path(instance)
  end
end
