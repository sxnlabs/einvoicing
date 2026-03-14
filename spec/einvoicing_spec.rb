# frozen_string_literal: true

require "spec_helper"

RSpec.describe Einvoicing do
  let(:seller) do
    Einvoicing::Party.new(
      name: "SXN Labs", siren: "898208145", siret: "89820814500018",
      vat_number: "FR46898208145", street: "5 Lot Coat an Lem",
      city: "Plouezoch", postal_code: "29252", country_code: "FR",
      email: "contact@sxnlabs.com"
    )
  end

  let(:buyer) do
    Einvoicing::Party.new(
      name: "Client SA", siren: "356000000", siret: "35600000000048",
      vat_number: "FR83356000000", street: "9 rue du Temple",
      city: "Paris", postal_code: "75004", country_code: "FR",
      email: "billing@client.fr"
    )
  end

  let(:invoice) do
    Einvoicing::Invoice.new(
      invoice_number: "INV-2024-001",
      issue_date: Date.new(2024, 1, 15),
      currency: "EUR",
      seller: seller,
      buyer: buyer,
      lines: [
        Einvoicing::LineItem.new(
          description: "Consulting",
          quantity: 1,
          unit_price: BigDecimal("1000"),
          vat_rate: BigDecimal("0.20")
        )
      ]
    )
  end

  describe ".xml" do
    it "generates CII XML by default" do
      xml = described_class.xml(invoice)
      expect(xml).to include("CrossIndustryInvoice")
      expect(xml).to include("INV-2024-001")
    end

    it "generates UBL XML when format: :ubl" do
      xml = described_class.xml(invoice, format: :ubl)
      expect(xml).to include("Invoice")
      expect(xml).to include("INV-2024-001")
    end

    it "raises ArgumentError for unknown format" do
      expect { described_class.xml(invoice, format: :unknown) }.to raise_error(ArgumentError, /unknown format/i)
    end
  end

  describe ".validate" do
    it "returns an empty array for a valid FR invoice" do
      errors = described_class.validate(invoice, market: :fr)
      expect(errors).to be_an(Array)
      expect(errors).to be_empty
    end

    it "raises ArgumentError for unknown market" do
      expect { described_class.validate(invoice, market: :xx) }.to raise_error(ArgumentError, /unknown market/i)
    end
  end

  describe ".process" do
    it "returns a result hash with valid: true for a valid invoice" do
      result = described_class.process(invoice)
      expect(result[:valid]).to be true
      expect(result[:errors]).to be_empty
      expect(result[:xml]).to include("CrossIndustryInvoice")
      expect(result[:pdf]).to be_nil
    end

    it "generates UBL when format: :ubl" do
      result = described_class.process(invoice, format: :ubl)
      expect(result[:valid]).to be true
      expect(result[:xml]).to include("Invoice")
    end

    it "never raises — returns errors hash on exception" do
      broken = Einvoicing::Invoice.new(invoice_number: nil, issue_date: nil, seller: seller, buyer: buyer, lines: [])
      result = described_class.process(broken)
      expect(result).to include(:valid, :errors, :xml)
    end
  end
end
