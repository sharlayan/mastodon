# frozen_string_literal: true

require 'fileutils'
require 'rbconfig'

module VoiceSignal
  class Build
    SDK_IMAGE = 'mcr.microsoft.com/dotnet/sdk:10.0'
    ARCHITECTURES = { 'x86_64' => 'x64', 'amd64' => 'x64', 'aarch64' => 'arm64', 'arm64' => 'arm64' }.freeze

    class Error < StandardError; end

    def initialize(root:, environment: ENV, cpu: RbConfig::CONFIG['host_cpu'], musl: File.exist?('/etc/alpine-release'))
      @root = root
      @environment = environment
      @cpu = cpu
      @musl = musl
    end

    def runtime
      architecture = ARCHITECTURES.fetch(@cpu) { raise Error, "Unsupported CPU architecture: #{@cpu}" }
      @musl ? "linux-musl-#{architecture}" : "linux-#{architecture}"
    end

    def output
      File.join(@root, 'voice_signal', 'publish')
    end

    def command
      dotnet = find_executable('dotnet')
      return [dotnet, *publish_arguments('voice_signal')] if dotnet

      docker = find_executable('docker')
      raise Error, 'Neither the .NET SDK (dotnet) nor docker is available to build the voice signal service' if docker.nil?

      [
        docker, 'run', '--rm', '--user', "#{Process.uid}:#{Process.gid}",
        '--env', 'HOME=/tmp', '--env', 'DOTNET_CLI_TELEMETRY_OPTOUT=1', '--env', 'DOTNET_NOLOGO=1',
        '--volume', "#{File.join(@root, 'voice_signal')}:/work/voice_signal", '--workdir', '/work',
        SDK_IMAGE, 'dotnet', *publish_arguments('voice_signal')
      ]
    end

    def run!
      build_command = command
      FileUtils.rm_rf(output)
      Dir.chdir(@root) { system(*build_command, exception: true) }
      FileUtils.rm_f(Dir[File.join(output, '*.json')])
      File.join(output, 'VoiceSignal')
    rescue RuntimeError, SystemCallError => e
      raise Error, e.message
    end

    private

    def publish_arguments(base)
      [
        'publish', File.join(base, 'src', 'VoiceSignal', 'VoiceSignal.csproj'),
        '--configuration', 'Release', '--runtime', runtime, '--self-contained', '--output', File.join(base, 'publish'),
        '-p:PublishSingleFile=true', '-p:DebugType=none'
      ]
    end

    def find_executable(name)
      @environment.fetch('PATH', '').split(File::PATH_SEPARATOR).each do |directory|
        path = File.join(directory, name)
        return path if File.file?(path) && File.executable?(path)
      end

      nil
    end
  end
end
