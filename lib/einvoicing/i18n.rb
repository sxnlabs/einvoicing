# frozen_string_literal: true

module Einvoicing
  # Thin wrapper around ::I18n with graceful fallback for standalone use.
  # When used outside Rails, ::I18n may not be available; in that case the
  # dotted key string is returned as-is.
  module I18n
    DEFAULT_LOCALE = :en

    def self.t(key, **options)
      return key.to_s unless defined?(::I18n)

      locale = options.delete(:locale) { ::I18n.locale rescue DEFAULT_LOCALE }
      ::I18n.t("einvoicing.#{key}", locale: locale, **options)
    rescue ::I18n::MissingTranslationData
      # Fallback to English if translation missing in current locale
      ::I18n.t("einvoicing.#{key}", locale: DEFAULT_LOCALE, **options)
    rescue StandardError
      key.to_s
    end
  end
end
