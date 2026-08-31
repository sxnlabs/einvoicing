# frozen_string_literal: true

# Must load before anything under lib/, or the files already required by the
# time SimpleCov starts are reported as entirely uncovered.
require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  enable_coverage :branch

  # A ratchet, not a target: these are the numbers this suite already reaches,
  # rounded down. Raise them when coverage improves, never lower them to make a
  # branch pass — an uncovered line is a missing test, not a threshold problem.
  #
  # It only applies to a full run. Running one file — in a TDD loop, from an
  # editor, in a pre-commit hook — would otherwise exit non-zero on coverage
  # with every test passing.
  #
  # And in CI only on the leg that sets COVERAGE_GATE. The branch table the
  # Coverage module produces is not identical across Ruby versions, and with
  # four branches of headroom the 3.2 leg could drop under the floor without a
  # line of code changing.
  # Any argument at all means a partial run: a file, an absolute path from an
  # editor, `-e "example name"`, `-t @tag`. Testing for a "spec/" prefix missed
  # every form but the first and gated a filtered subset against the whole
  # suite's floor.
  full_run = ARGV.empty?
  gated = ENV["CI"] ? ENV["COVERAGE_GATE"] == "1" : true

  minimum_coverage line: 90, branch: 76 if full_run && gated
end

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
      vat_number:  "FR39356000000"
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

  def self.invoice(lines: [ line ])
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
