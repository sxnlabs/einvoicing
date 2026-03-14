# frozen_string_literal: true

require "date"
require "bigdecimal"
require "bigdecimal/util"

require_relative "einvoicing/version"
require_relative "einvoicing/errors"
require_relative "einvoicing/tax"
require_relative "einvoicing/party"
require_relative "einvoicing/siret_lookup"
require_relative "einvoicing/fr"
require_relative "einvoicing/line_item"
require_relative "einvoicing/invoice"
require_relative "einvoicing/xml_builder"
require_relative "einvoicing/formats/cii"
require_relative "einvoicing/formats/ubl"
require_relative "einvoicing/formats/facturx"
require_relative "einvoicing/i18n"
require_relative "einvoicing/validators/base"
require_relative "einvoicing/validators/fr"
require_relative "einvoicing/validators/peppol"
require_relative "einvoicing/invoiceable"
require_relative "einvoicing/rails/concern"
require_relative "einvoicing/ppf"

# Optional Rails engine — only load when Rails is available.
if defined?(Rails::Engine)
  require_relative "einvoicing/rails/engine"
end

# Einvoicing — EU electronic invoicing for Ruby.
#
# Generates EN 16931-compliant invoices in Factur-X (PDF/A-3 + CII XML),
# UBL 2.1, and CII D16B formats. Validates French B2B compliance (SIREN,
# SIRET, TVA). Provides a Rails concern for ActiveRecord models.
#
# @example Quick start
#   seller = Einvoicing::Party.new(name: "Acme SAS", siren: "356000000", vat_number: "FR83356000000")
#   buyer  = Einvoicing::Party.new(name: "Client SA", siren: "552032534")
#   line   = Einvoicing::LineItem.new(description: "Consulting", quantity: 1, unit_price: 1000.00)
#
#   invoice = Einvoicing::Invoice.new(
#     invoice_number: "INV-2024-001",
#     issue_date: Date.today,
#     seller: seller,
#     buyer: buyer,
#     lines: [line]
#   )
#
#   xml = Einvoicing::Formats::CII.generate(invoice)
#   ubl = Einvoicing::Formats::UBL.generate(invoice)
module Einvoicing
  # ─── Top-level convenience API ────────────────────────────────────────────

  # Generate XML from an invoice.
  # @param invoice [Einvoicing::Invoice]
  # @param format [Symbol] :cii (default, Factur-X) or :ubl (Peppol BIS 3.0)
  # @return [String] XML document
  def self.xml(invoice, format: :cii)
    case format
    when :cii then Formats::CII.generate(invoice)
    when :ubl then Formats::UBL.generate(invoice)
    else raise ArgumentError, Einvoicing::I18n.t("formats.unknown_format", fmt: format.inspect)
    end
  end

  # Embed a Factur-X CII XML into a PDF, returning a PDF/A-3 binary.
  # @param pdf_data [String] raw PDF binary
  # @param invoice_or_xml [Invoice, String] Invoice (CII generated internally) or raw XML string
  # @return [String] Factur-X PDF/A-3 binary
  def self.embed(pdf_data, invoice_or_xml)
    xml_str = invoice_or_xml.is_a?(String) ? invoice_or_xml : xml(invoice_or_xml, format: :cii)
    Formats::FacturX.embed(pdf_data, xml_str)
  end

  # Validate an invoice against a market's rules.
  # @param invoice [Einvoicing::Invoice]
  # @param market [Symbol] :fr (default)
  # @return [Array<Hash>] array of { field:, error:, message: } — empty means valid
  def self.validate(invoice, market: :fr)
    case market
    when :fr then Validators::FR.validate(invoice)
    else raise ArgumentError, Einvoicing::I18n.t("formats.unknown_market", market: market.inspect)
    end
  end

  # Full pipeline: validate → generate XML → optionally embed in PDF.
  # Never raises — errors are returned in the result hash.
  # @param invoice [Einvoicing::Invoice]
  # @param format [Symbol] :cii or :ubl
  # @param market [Symbol] :fr
  # @param pdf [String, nil] optional raw PDF binary to embed into
  # @return [Hash] { valid:, errors:, xml:, pdf: }
  def self.process(invoice, format: :cii, market: :fr, pdf: nil)
    errors  = validate(invoice, market: market)
    xml_str = xml(invoice, format: format)
    pdf_out = pdf ? embed(pdf, xml_str) : nil
    { valid: errors.empty?, errors: errors, xml: xml_str, pdf: pdf_out }
  rescue StandardError => e
    { valid: false, errors: [ { field: :unknown, error: :exception, message: e.message } ], xml: nil, pdf: nil }
  end
end
