# frozen_string_literal: true

require "date"
require "einvoicing"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.warnings = true
  config.order = :random
  Kernel.srand config.seed
end

# Shared test fixtures.
module Fixtures
  def self.seller
    Einvoicing::Party.new(
      name:        "Acme SAS",
      street:      "1 rue de la Paix",
      city:        "Paris",
      postal_code: "75001",
      country_code: "FR",
      siren:       "356000000",       # La Poste — known-valid Luhn SIREN
      vat_number:  "FR83356000000"
    )
  end

  def self.buyer
    Einvoicing::Party.new(
      name:        "Client SA",
      street:      "10 avenue des Champs",
      city:        "Lyon",
      postal_code: "69001",
      country_code: "FR",
      siren:       "552032534"        # Renault — known-valid Luhn SIREN
    )
  end

  def self.line(vat_rate: 0.20)
    Einvoicing::LineItem.new(
      description: "Software consulting",
      quantity:    5,
      unit_price:  200.00,
      vat_rate:    vat_rate
    )
  end

  def self.invoice(lines: [line])
    Einvoicing::Invoice.new(
      invoice_number:    "INV-2024-001",
      issue_date:        Date.new(2024, 1, 15),
      due_date:          Date.new(2024, 2, 15),
      seller:            seller,
      buyer:             buyer,
      lines:             lines,
      payment_reference: "PO-2024-001"
    )
  end
end
