# frozen_string_literal: true

module Einvoicing
  module Validators
    # French invoice validator.
    # Checks SIREN, SIRET, TVA (VAT) number format and Luhn checksum, plus
    # mandatory invoice fields for French B2B compliance.
    #
    # @example
    #   errors = Einvoicing::Validators::FR.validate(invoice)
    #   errors.empty? # => true if valid
    #
    #   Einvoicing::Validators::FR.validate!(invoice) # raises on failure
    module FR
      include Base

      SIREN_RE  = /\A\d{9}\z/
      SIRET_RE  = /\A\d{14}\z/
      # FR VAT: "FR" + 2 alphanumeric chars + 9-digit SIREN
      VAT_RE    = /\AFR[A-Z0-9]{2}\d{9}\z/
      INV_NUM_RE = /\A[\w\-\/]{1,35}\z/

      # @param invoice [Einvoicing::Invoice]
      # @return [Array<Hash>] list of error hashes ({ field:, error:, message: }); empty if valid
      def self.validate(invoice)
        [
          *validate_invoice_fields(invoice),
          *validate_party(invoice.seller, :seller),
          *validate_party(invoice.buyer,  :buyer),
          *validate_lines(invoice.lines)
        ]
      end

      # @raise [Einvoicing::Validators::ValidationError] if invalid
      def self.validate!(invoice)
        errors = validate(invoice)
        raise ValidationError, errors.map { |e| e[:message] }.join("; ") unless errors.empty?

        true
      end

      # Validate a single SIREN number.
      # @param siren [String]
      # @return [Boolean]
      def self.valid_siren?(siren)
        return false unless siren.to_s.match?(SIREN_RE)

        Base.luhn_valid?(siren.to_s)
      end

      # Validate a single SIRET number.
      # @param siret [String]
      # @return [Boolean]
      def self.valid_siret?(siret)
        return false unless siret.to_s.match?(SIRET_RE)

        Base.luhn_valid?(siret.to_s)
      end

      # Validate a French VAT number format.
      # @param vat [String] e.g. "FR12123456789"
      # @return [Boolean]
      def self.valid_vat_number?(vat)
        vat.to_s.match?(VAT_RE)
      end

      # Validate an invoice number format (alphanumeric, dashes, slashes, 1-35 chars).
      # @param number [String]
      # @return [Boolean]
      def self.valid_invoice_number?(number)
        number.to_s.match?(INV_NUM_RE)
      end

      # -- Private helpers ---------------------------------------------------

      def self.validate_invoice_fields(invoice)
        errors = [
          Base.presence(invoice.invoice_number, :invoice_number,
                        Einvoicing::I18n.t("errors.invoice.number_missing"),
                        error: :number_missing),
          Base.presence(invoice.issue_date, :issue_date,
                        Einvoicing::I18n.t("errors.invoice.issue_date_missing"),
                        error: :issue_date_missing),
          Base.presence(invoice.currency, :currency,
                        Einvoicing::I18n.t("errors.invoice.currency_missing"),
                        error: :currency_missing)
        ].compact
        unless valid_invoice_number?(invoice.invoice_number.to_s)
          errors << { field: :invoice_number, error: :number_invalid,
                      message: Einvoicing::I18n.t("errors.invoice.number_invalid") }
        end
        errors
      end
      private_class_method :validate_invoice_fields

      def self.validate_party(party, role)
        name_field = :"#{role}_name"
        errors = [
          Base.presence(party&.name, name_field,
                        Einvoicing::I18n.t("errors.#{role}.name_missing"),
                        error: :name_missing)
        ].compact
        return errors if party.nil?

        siren = party.siren_number
        if siren && !valid_siren?(siren)
          errors << { field: :"#{role}_siren", error: :siren_invalid,
                      message: Einvoicing::I18n.t("errors.#{role}.siren_invalid") }
        end

        if party.siret && !valid_siret?(party.siret)
          errors << { field: :"#{role}_siret", error: :siret_invalid,
                      message: Einvoicing::I18n.t("errors.#{role}.siret_invalid") }
        end

        if party.vat_number && !valid_vat_number?(party.vat_number)
          errors << { field: :"#{role}_vat_number", error: :vat_number_invalid,
                      message: Einvoicing::I18n.t("errors.#{role}.vat_number_invalid") }
        end

        errors
      end
      private_class_method :validate_party

      def self.validate_lines(lines)
        if lines.nil? || lines.empty?
          return [{ field: :lines, error: :lines_empty,
                    message: Einvoicing::I18n.t("errors.invoice.lines_empty") }]
        end

        lines.each_with_index.flat_map do |line, idx|
          n = idx + 1
          [
            (if line.description.to_s.strip.empty?
               { field: :"line_#{n}_description", error: :description_missing,
                 message: Einvoicing::I18n.t("errors.line.description_missing", index: n) }
             end),
            (unless line.quantity.to_f.positive?
               { field: :"line_#{n}_quantity", error: :quantity_invalid,
                 message: Einvoicing::I18n.t("errors.line.quantity_invalid", index: n) }
             end),
            (if line.unit_price.to_f.negative?
               { field: :"line_#{n}_unit_price", error: :unit_price_invalid,
                 message: Einvoicing::I18n.t("errors.line.unit_price_invalid", index: n) }
             end),
            (unless [0.0, 0.055, 0.10, 0.20].include?(line.vat_rate.to_f.round(3))
               { field: :"line_#{n}_vat_rate", error: :vat_rate_invalid,
                 message: Einvoicing::I18n.t("errors.line.vat_rate_invalid", index: n) }
             end)
          ]
        end.compact
      end
      private_class_method :validate_lines
    end
  end
end
