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
      SIREN_RE   = /\A\d{9}\z/
      SIRET_RE   = /\A\d{14}\z/
      # FR VAT: "FR" + 2 alphanumeric chars + 9-digit SIREN
      VAT_RE     = /\AFR[A-Z0-9]{2}\d{9}\z/
      INV_NUM_RE = /\A[\w\-\/]{1,35}\z/
      # IBAN: country code (2 alpha) + 2 check digits + BBAN (11-30 alphanumeric) = 15-34 total
      IBAN_RE    = /\A[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}\z/
      # BIC: 4 alpha (institution) + 2 alpha (country) + 2 alphanumeric (location) + optional 3 alphanumeric (branch)
      BIC_RE     = /\A[A-Z]{4}[A-Z]{2}[A-Z0-9]{2}([A-Z0-9]{3})?\z/

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

      # Validate an IBAN (ISO 13616 format + mod-97 checksum).
      # @param iban [String]
      # @return [Boolean]
      def self.valid_iban?(iban)
        str = iban.to_s.gsub(/\s/, "").upcase
        return false unless str.match?(IBAN_RE)

        # Move first 4 chars to end, replace each letter with its numeric value (A=10..Z=35)
        rearranged = str[4..] + str[0..3]
        numeric = rearranged.chars.map { |c| c =~ /[A-Z]/ ? (c.ord - 55).to_s : c }.join
        numeric.to_i % 97 == 1
      end

      # Validate a BIC (ISO 9362) — 8 or 11 chars.
      # @param bic [String]
      # @return [Boolean]
      def self.valid_bic?(bic)
        bic.to_s.match?(BIC_RE)
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
        if invoice.document_type == :credit_note &&
           invoice.original_invoice_number.to_s.strip.empty?
          errors << { field: :original_invoice_number, error: :original_invoice_number_missing,
                      message: Einvoicing::I18n.t("errors.invoice.original_invoice_number_missing") }
        end
        if invoice.iban && !valid_iban?(invoice.iban)
          errors << { field: :iban, error: :iban_invalid,
                      message: Einvoicing::I18n.t("errors.invoice.iban_invalid") }
        end
        if invoice.bic && !valid_bic?(invoice.bic)
          errors << { field: :bic, error: :bic_invalid,
                      message: Einvoicing::I18n.t("errors.invoice.bic_invalid") }
        end
        if invoice.prepaid_amount.negative?
          errors << { field: :prepaid_amount, error: :prepaid_amount_negative,
                      message: Einvoicing::I18n.t("errors.invoice.prepaid_amount_negative") }
        elsif invoice.prepaid_amount > invoice.gross_total
          errors << { field: :prepaid_amount, error: :prepaid_amount_exceeds_total,
                      message: Einvoicing::I18n.t("errors.invoice.prepaid_amount_exceeds_total") }
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
          return [ { field: :lines, error: :lines_empty,
                    message: Einvoicing::I18n.t("errors.invoice.lines_empty") } ]
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
            (unless [ 0.0, 0.055, 0.10, 0.20 ].include?(line.vat_rate.to_f.round(3))
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
