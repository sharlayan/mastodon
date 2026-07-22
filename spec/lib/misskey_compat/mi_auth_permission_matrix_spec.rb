# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MisskeyCompat::MiAuth do
  def routed_actions
    Rails.application.routes.routes.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |route, memo|
      controller = route.defaults[:controller]
      next unless controller&.start_with?('api/misskey_compat/')

      memo["#{controller.camelize}Controller"] << route.defaults[:action]
    end
  end

  def condition_met?(controller, condition)
    case condition
    when AbstractController::Callbacks::ActionFilter then condition.match?(controller)
    when Proc then controller.instance_exec(controller, &condition)
    when String then controller.instance_eval(condition)
    when Symbol then controller.send(condition)
    else true
    end
  end

  def credentialed_action?(klass, callback, action)
    controller = klass.new
    controller.define_singleton_method(:action_name) { action }

    callback.instance_variable_get(:@if).all? { |condition| condition_met?(controller, condition) } &&
      callback.instance_variable_get(:@unless).none? { |condition| condition_met?(controller, condition) }
  end

  def credentialed_actions
    routed_actions.flat_map do |name, actions|
      klass = name.safe_constantize
      next [] if klass.nil?

      callback = klass._process_action_callbacks.find { |cb| cb.filter == :require_user! }
      next [] if callback.nil?

      actions.uniq.filter_map do |action|
        [klass, action] if credentialed_action?(klass, callback, action)
      end
    end
  end

  def compat_controllers
    Rails.root.glob('app/controllers/api/misskey_compat/*.rb').filter_map do |path|
      klass = "Api::MisskeyCompat::#{File.basename(path, '.rb').camelize}".safe_constantize
      klass if klass.is_a?(Class) && klass < Api::MisskeyCompat::BaseController
    end
  end

  describe 'the credentialed action detection itself' do
    it 'honours the only: option so the matrix below is not evaluated against the wrong actions' do
      detected = credentialed_actions.select { |klass, _| klass == Api::MisskeyCompat::AccountsController }.map(&:last)

      expect(detected).to include('update_memo')
      expect(detected).to_not include('index')
    end
  end

  describe 'the permission matrix' do
    it 'requires a MiAuth permission for every action behind require_user!' do
      unmapped = credentialed_actions.reject { |klass, action| klass.misskey_action_permissions[action] }

      expect(unmapped.map { |klass, action| "#{klass}##{action}" }).to be_empty
    end

    it 'only declares permissions that a MiAuth grant can actually hold' do
      declared = compat_controllers.flat_map { |klass| klass.misskey_action_permissions.values }.uniq

      expect(declared - described_class::SUPPORTED_PERMISSIONS).to be_empty
    end

    it 'never lets a read permission satisfy a write action' do
      mismatched = compat_controllers.flat_map do |klass|
        klass.misskey_write_actions.filter_map do |action|
          permission = klass.misskey_action_permissions[action]
          "#{klass}##{action} => #{permission.inspect}" if permission.nil? || permission.start_with?('read:')
        end
      end

      expect(mismatched).to be_empty
    end
  end
end
