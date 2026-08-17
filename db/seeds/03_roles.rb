# frozen_string_literal: true

# Pre-create base role
UserRole.everyone

# Create default roles defined in config file
default_roles = YAML.load_file(Rails.root.join('config', 'roles.yml'))

default_roles.each_value do |config|
  permissions = config['permissions'].dup
  extra_permissions = (config['extra_permissions'] || []).dup
  permissions << 'invite_users' if RoleplayModeHelper.roleplay_mode? && %w(Moderator Admin).include?(config['name'])

  UserRole.create_with(position: config['position'], permissions_as_keys: permissions, extra_permissions_as_keys: extra_permissions, highlighted: true).find_or_create_by(name: config['name'])
end
