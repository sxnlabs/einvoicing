# frozen_string_literal: true

require "i18n"

module Einvoicing
  # Thin wrapper around ::I18n for gem-internal translations.
  # Loads the gem's own locale files on setup; in Rails apps the engine
  # already handles the load_path, so duplicates are skipped.
  module I18n
    DEFAULT_LOCALE = :en
    LOCALES_PATH = File.expand_path("../../config/locales", __dir__)

    def self.setup
      locale_files = Dir[File.join(LOCALES_PATH, "*.yml")]
      new_files = locale_files - ::I18n.load_path
      return if new_files.empty?

      ::I18n.load_path += new_files
      ::I18n.backend.load_translations
    end

    def self.t(key, **options)
      locale = options.delete(:locale) { ::I18n.locale }
      ::I18n.t("einvoicing.#{key}", locale: locale, **options)
    rescue ::I18n::MissingTranslationData
      ::I18n.t("einvoicing.#{key}", locale: DEFAULT_LOCALE, **options)
    rescue StandardError
      key.to_s
    end
  end
end

Einvoicing::I18n.setup
