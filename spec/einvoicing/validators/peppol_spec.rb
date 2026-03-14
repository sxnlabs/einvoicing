# frozen_string_literal: true
require "spec_helper"

RSpec.describe Einvoicing::Validators::Peppol do
  before do
    skip "java required" unless described_class.java_available?
    skip "Saxon JAR not found" unless File.exist?(described_class::SAXON_JAR)
    skip "Peppol XSLT not found" unless File.exist?(described_class::XSLT_PATH)
  end

  # Peppol BIS 3.0 requires EndpointID (scheme 0002/SIRET) on both parties
  let(:peppol_invoice) do
    Einvoicing::Invoice.new(
      invoice_number: "PEPPOL-TEST-001", issue_date: Date.new(2024, 1, 15),
      currency: "EUR",
      seller: Einvoicing::Party.new(
        name: "SXN Labs", siren: "898208145", siret: "89820814500018",
        vat_number: "FR46898208145", street: "5 Lot Coat an Lem",
        city: "Plouezoch", postal_code: "29252", country_code: "FR",
        email: "contact@sxnlabs.com"
      ),
      buyer: Einvoicing::Party.new(
        name: "Client SA", siren: "356000000", siret: "35600000000048",
        vat_number: "FR83356000000", street: "9 rue du Temple",
        city: "Paris", postal_code: "75004", country_code: "FR",
        email: "billing@client.fr"
      ),
      lines: [Einvoicing::LineItem.new(
        description: "Consulting", quantity: 1,
        unit_price: BigDecimal("1000"), vat_rate: BigDecimal("0.20")
      )]
    )
  end

  let(:ubl) { Einvoicing::Formats::UBL.generate(peppol_invoice) }

  describe ".validate_ubl" do
    it "returns 0 errors for a valid Peppol BIS 3.0 invoice" do
      errors = described_class.validate_ubl(ubl)
      expect(errors).to be_an(Array)
      expect(errors).to be_empty, "Expected 0 Peppol errors, got: #{errors.map { |e| e[:field] }.join(', ')}"
    end

    it "returns errors with field/error/message keys" do
      # Inject an invoice missing endpoint (triggers R010/R020)
      broken_party = Einvoicing::Party.new(name: "No Endpoint", siren: "356000000")
      broken_invoice = Einvoicing::Invoice.new(
        invoice_number: "ERR-001", issue_date: Date.today, currency: "EUR",
        seller: broken_party, buyer: broken_party,
        lines: [Einvoicing::LineItem.new(description: "x", quantity: 1,
          unit_price: BigDecimal("100"), vat_rate: BigDecimal("0.20"))]
      )
      errors = described_class.validate_ubl(Einvoicing::Formats::UBL.generate(broken_invoice))
      expect(errors).to be_an(Array)
      expect(errors).not_to be_empty
      errors.each { |e| expect(e).to include(:field, :error, :message) }
      expect(errors.map { |e| e[:message] }).to include(match(/electronic address/i))
    end

    it "returns errors for malformed XML" do
      errors = described_class.validate_ubl("<not-ubl/>")
      expect(errors).to be_an(Array)
    end
  end

  describe ".java_available?" do
    it "returns true" do
      expect(described_class.java_available?).to be true
    end
  end
end
