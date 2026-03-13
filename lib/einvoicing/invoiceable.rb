# frozen_string_literal: true

module Einvoicing
  # ActiveSupport::Concern that adds e-invoicing capabilities to an
  # ActiveRecord model.
  #
  # The model must respond to the following methods (columns or Ruby methods):
  #   invoice_number, issue_date, due_date, currency,
  #   einvoicing_seller, einvoicing_buyer, einvoicing_lines
  #
  # @example
  #   class Invoice < ApplicationRecord
  #     include Einvoicing::Invoiceable
  #
  #     def einvoicing_seller
  #       Einvoicing::Party.new(
  #         name:       company.name,
  #         siren:      company.siren,
  #         vat_number: company.vat_number,
  #         street:     company.street,
  #         city:       company.city,
  #         postal_code: company.postal_code
  #       )
  #     end
  #
  #     def einvoicing_buyer
  #       Einvoicing::Party.new(name: client.name, siren: client.siren)
  #     end
  #
  #     def einvoicing_lines
  #       line_items.map do |li|
  #         Einvoicing::LineItem.new(
  #           description: li.description,
  #           quantity:    li.quantity,
  #           unit_price:  li.unit_price,
  #           vat_rate:    li.vat_rate
  #         )
  #       end
  #     end
  #   end
  module Invoiceable
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      # Override to use a different validator. Defaults to FR.
      # @example
      #   self.einvoicing_validator = Einvoicing::Validators::DE
      def einvoicing_validator
        @einvoicing_validator || Einvoicing::Validators::FR
      end

      def einvoicing_validator=(validator)
        @einvoicing_validator = validator
      end
    end

    # Build an Einvoicing::Invoice from this record.
    # @return [Einvoicing::Invoice]
    def to_einvoice
      has_due_date = self.class.respond_to?(:column_names) \
        ? self.class.column_names.include?("due_date") \
        : respond_to?(:due_date)

      Einvoicing::Invoice.new(
        invoice_number: invoice_number,
        issue_date:     issue_date,
        due_date:       has_due_date ? due_date : nil,
        currency:       respond_to?(:currency) ? (currency || "EUR") : "EUR",
        seller:         einvoicing_seller,
        buyer:          einvoicing_buyer,
        lines:          einvoicing_lines
      )
    end

    # Generate CII D16B XML string.
    # @return [String]
    def to_cii_xml
      Einvoicing::Formats::CII.generate(to_einvoice)
    end

    # Generate UBL 2.1 XML string.
    # @return [String]
    def to_ubl_xml
      Einvoicing::Formats::UBL.generate(to_einvoice)
    end

    # Generate Factur-X PDF by embedding CII XML into an existing PDF blob.
    # @param pdf_data [String] original PDF binary
    # @return [String] Factur-X PDF binary
    def to_facturx(pdf_data)
      xml = to_cii_xml
      Einvoicing::Formats::FacturX.embed(pdf_data, xml)
    end

    # Validate the invoice using the configured validator.
    # @return [Array<Hash>] list of error hashes ({ field:, error:, message: })
    def einvoicing_errors
      self.class.einvoicing_validator.validate(to_einvoice)
    end

    # @return [Boolean]
    def einvoicing_valid?
      einvoicing_errors.empty?
    end

    # Raise ValidationError unless valid.
    def validate_einvoice!
      self.class.einvoicing_validator.validate!(to_einvoice)
    end

    # Stub: override in your model or configure an adapter.
    # Returns a hash with :status and optionally :reference.
    def transmit!(adapter: nil)
      raise NotImplementedError,
            "Configure a transmission adapter or override #transmit! in #{self.class}"
    end
  end
end
