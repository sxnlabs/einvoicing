# frozen_string_literal: true

require_relative "einvoicing/version"
require_relative "einvoicing/tax"
require_relative "einvoicing/party"
require_relative "einvoicing/line_item"
require_relative "einvoicing/invoice"
require_relative "einvoicing/xml_builder"
require_relative "einvoicing/formats/cii"
require_relative "einvoicing/formats/ubl"
require_relative "einvoicing/formats/facturx"
require_relative "einvoicing/i18n"
require_relative "einvoicing/validators/base"
require_relative "einvoicing/validators/fr"
require_relative "einvoicing/rails/concern"

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
end
