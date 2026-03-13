# frozen_string_literal: true

module Einvoicing
  # Thin wrapper around ::I18n with graceful fallback for standalone use.
  # When used outside Rails, ::I18n may not be available; in that case the
  # dotted key string is returned as-is.
  module I18n
    def self.t(key, **options)
      return key.to_s unless defined?(::I18n)

      ::I18n.t("einvoicing.#{key}", **options)
    rescue ::I18n::MissingTranslationData
      key.to_s
    end
  end
end
