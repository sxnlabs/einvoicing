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
          Base.presence(invoice.invoice_number, :invoice_number, "Invoice number is required"),
          Base.presence(invoice.issue_date,     :issue_date,     "Issue date is required"),
          Base.presence(invoice.currency,       :currency,       "Currency is required")
        ].compact
        unless valid_invoice_number?(invoice.invoice_number.to_s)
          errors << { field: :invoice_number, error: :invalid,
                      message: "Invoice number '#{invoice.invoice_number}' is invalid " \
                               "(1-35 alphanumeric/dash/slash chars)" }
        end
        errors
      end
      private_class_method :validate_invoice_fields

      def self.validate_party(party, role)
        name_field = :"#{role}_name"
        errors = [Base.presence(party&.name, name_field, "#{role.capitalize} name is required")].compact
        return errors if party.nil?

        siren = party.siren_number
        if siren && !valid_siren?(siren)
          errors << { field: :"#{role}_siren", error: :invalid,
                      message: "#{role.capitalize} SIREN '#{siren}' is invalid " \
                               "(must be 9 digits with valid Luhn checksum)" }
        end

        if party.siret && !valid_siret?(party.siret)
          errors << { field: :"#{role}_siret", error: :invalid,
                      message: "#{role.capitalize} SIRET '#{party.siret}' is invalid " \
                               "(must be 14 digits with valid Luhn checksum)" }
        end

        if party.vat_number && !valid_vat_number?(party.vat_number)
          errors << { field: :"#{role}_vat_number", error: :invalid,
                      message: "#{role.capitalize} VAT number '#{party.vat_number}' is invalid " \
                               "(expected FR + 2 chars + 9 digits)" }
        end

        errors
      end
      private_class_method :validate_party

      def self.validate_lines(lines)
        if lines.nil? || lines.empty?
          return [{ field: :lines, error: :empty, message: "Invoice must have at least one line item" }]
        end

        lines.each_with_index.flat_map do |line, idx|
          n = idx + 1
          [
            (if line.description.to_s.strip.empty?
               { field: :"line_#{n}_description", error: :blank, message: "Line #{n}: description is required" }
             end),
            (unless line.quantity.to_f.positive?
               { field: :"line_#{n}_quantity", error: :invalid, message: "Line #{n}: quantity must be positive" }
             end),
            (if line.unit_price.to_f.negative?
               { field: :"line_#{n}_unit_price", error: :invalid, message: "Line #{n}: unit_price must be non-negative" }
             end),
            (unless [0.0, 0.055, 0.10, 0.20].include?(line.vat_rate.to_f.round(3))
               { field: :"line_#{n}_vat_rate", error: :invalid,
                 message: "Line #{n}: vat_rate #{line.vat_rate} is not a standard French rate (0, 5.5%, 10%, 20%)" }
             end)
          ]
        end.compact
      end
      private_class_method :validate_lines
    end
  end
end
