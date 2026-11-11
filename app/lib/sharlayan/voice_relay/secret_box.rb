# frozen_string_literal: true

module Sharlayan
  module VoiceRelay
    module SecretBox
      VERSION = 'v1'
      CONTEXT = 'sharlayan voice relay provider secret v1'
      IV_LENGTH = 12
      TAG_LENGTH = 16

      module_function

      def encrypt(plaintext)
        cipher = OpenSSL::Cipher.new('aes-256-gcm').encrypt
        cipher.key = key
        iv = SecureRandom.random_bytes(IV_LENGTH)
        cipher.iv = iv
        cipher.auth_data = ''
        ciphertext = cipher.update(plaintext.to_s) + cipher.final

        "#{VERSION}:#{Base64.strict_encode64(iv + cipher.auth_tag + ciphertext)}"
      end

      def decrypt(payload)
        version, encoded = payload.to_s.split(':', 2)
        raise Error.new('MISSING_KEY', 400) unless version == VERSION && encoded.present?

        raw = Base64.strict_decode64(encoded)
        raise Error.new('MISSING_KEY', 400) if raw.bytesize <= IV_LENGTH + TAG_LENGTH

        decipher = OpenSSL::Cipher.new('aes-256-gcm').decrypt
        decipher.key = key
        decipher.iv = raw.byteslice(0, IV_LENGTH)
        decipher.auth_tag = raw.byteslice(IV_LENGTH, TAG_LENGTH)
        decipher.auth_data = ''
        plaintext = decipher.update(raw.byteslice((IV_LENGTH + TAG_LENGTH)..)) + decipher.final

        plaintext.force_encoding(Encoding::UTF_8)
      rescue OpenSSL::Cipher::CipherError, ArgumentError
        raise Error.new('MISSING_KEY', 400)
      end

      def key
        OpenSSL::HMAC.digest('SHA256', Rails.application.secret_key_base, CONTEXT)
      end
    end
  end
end
