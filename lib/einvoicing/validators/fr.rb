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
      # @return [Array<String>] list of error messages; empty if valid
      def self.validate(invoice)
        errors = []
        errors += validate_invoice_fields(invoice)
        errors += validate_party(invoice.seller, "Seller")
        errors += validate_party(invoice.buyer,  "Buyer")
        errors += validate_lines(invoice.lines)
        errors
      end

      # @raise [Einvoicing::Validators::ValidationError] if invalid
      def self.validate!(invoice)
        errors = validate(invoice)
        raise ValidationError, errors.join("; ") unless errors.empty?

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
        errors = []
        errors << Base.presence(invoice.invoice_number, "Invoice number")
        unless valid_invoice_number?(invoice.invoice_number.to_s)
          errors << "Invoice number '#{invoice.invoice_number}' is invalid (1-35 alphanumeric/dash/slash chars)"
        end
        errors << Base.presence(invoice.issue_date, "Issue date")
        errors << Base.presence(invoice.currency,   "Currency")
        errors.compact
      end
      private_class_method :validate_invoice_fields

      def self.validate_party(party, label)
        errors = []
        errors << Base.presence(party&.name, "#{label} name")
        return errors if party.nil?

        siren = party.siren_number
        if siren
          unless valid_siren?(siren)
            errors << "#{label} SIREN '#{siren}' is invalid (must be 9 digits with valid Luhn checksum)"
          end
        end

        if party.siret
          unless valid_siret?(party.siret)
            errors << "#{label} SIRET '#{party.siret}' is invalid (must be 14 digits with valid Luhn checksum)"
          end
        end

        if party.vat_number
          unless valid_vat_number?(party.vat_number)
            errors << "#{label} VAT number '#{party.vat_number}' is invalid (expected FR + 2 chars + 9 digits)"
          end
        end

        errors.compact
      end
      private_class_method :validate_party

      def self.validate_lines(lines)
        errors = []
        if lines.nil? || lines.empty?
          errors << "Invoice must have at least one line item"
          return errors
        end
        lines.each_with_index do |line, idx|
          errors << "Line #{idx + 1}: description is required" if line.description.to_s.strip.empty?
          errors << "Line #{idx + 1}: quantity must be positive" unless line.quantity.to_f.positive?
          errors << "Line #{idx + 1}: unit_price must be non-negative" if line.unit_price.to_f.negative?
          unless [0.0, 0.055, 0.10, 0.20].include?(line.vat_rate.to_f.round(3))
            errors << "Line #{idx + 1}: vat_rate #{line.vat_rate} is not a standard French rate (0, 5.5%, 10%, 20%)"
          end
        end
        errors
      end
      private_class_method :validate_lines
    end
  end
end
