# frozen_string_literal: true

Regexp.timeout = ENV.fetch('REGEXP_TIMEOUT', 2).to_f if Regexp.respond_to?(:timeout=)
