# frozen_string_literal: true

require 'puma/plugin'
require_relative '../../voice_signal/launcher'

Puma::Plugin.create do
  def start(launcher)
    log = ->(message) { launcher.log_writer.log(message) }
    root = File.expand_path('../../..', __dir__)
    voice_signal = VoiceSignal::Launcher.from_environment(root:, log:)
    return if voice_signal.nil?

    launcher.events.after_booted { voice_signal.start }
    launcher.events.before_restart { voice_signal.stop }
    launcher.events.after_stopped { voice_signal.stop }
  rescue VoiceSignal::Launcher::ConfigurationError => e
    log.call("[voice-signal] not started: #{e.message}")
  end
end
