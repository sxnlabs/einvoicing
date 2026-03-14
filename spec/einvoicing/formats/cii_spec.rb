# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/schema_validation"

RSpec.describe Einvoicing::Formats::CII do
  include SchemaValidation

  let(:invoice) { Fixtures.invoice }
  let(:xml)     { described_class.generate(invoice) }

  it "generates a non-empty XML string" do
    expect(xml).to be_a(String)
    expect(xml).not_to be_empty
  end

  it "starts with XML declaration" do
    expect(xml).to start_with('<?xml version="1.0" encoding="UTF-8"?>')
  end

  it "includes the CrossIndustryInvoice root element" do
    expect(xml).to include("rsm:CrossIndustryInvoice")
  end

  it "includes the EN 16931 guideline ID" do
    expect(xml).to include("urn:cen.eu:en16931:2017")
  end

  it "includes the invoice number" do
    expect(xml).to include("INV-2024-001")
  end

  it "includes the invoice type code 380" do
    expect(xml).to include("<ram:TypeCode>380</ram:TypeCode>")
  end

  it "includes issue date in YYYYMMDD format" do
    expect(xml).to include("20240115")
  end

  it "includes due date in YYYYMMDD format" do
    expect(xml).to include("20240215")
  end

  it "includes seller name" do
    expect(xml).to include("Acme SAS")
  end

  it "includes buyer name" do
    expect(xml).to include("Client SA")
  end

  it "includes seller SIREN with scheme 0002" do
    expect(xml).to include('schemeID="0002"')
    expect(xml).to include("356000000")
  end

  it "includes seller VAT number" do
    expect(xml).to include("FR83356000000")
  end

  it "includes line item description" do
    expect(xml).to include("Software consulting")
  end

  it "includes net total" do
    expect(xml).to include("1000.00")
  end

  it "includes VAT rate 20%" do
    expect(xml).to include("20.00")
  end

  it "includes grand total" do
    expect(xml).to include("1200.00")
  end

  it "includes currency code" do
    expect(xml).to include("EUR")
  end

  it "is well-formed XML" do
    require "rexml/document"
    doc = REXML::Document.new(xml)
    expect(doc.root).not_to be_nil
    expect(doc.root.name).to eq("CrossIndustryInvoice")
  end

  context "with payment means" do
    let(:invoice) do
      Einvoicing::Invoice.new(
        invoice_number:     "INV-2024-001",
        issue_date:         Date.new(2024, 1, 15),
        due_date:           Date.new(2024, 2, 15),
        seller:             Fixtures.seller,
        buyer:              Fixtures.buyer,
        lines:              [ Fixtures.line ],
        payment_means_code: 30,
        iban:               "FR7630006000011234567890189",
        bic:                "BNPAFRPP"
      )
    end

    it "includes SpecifiedTradeSettlementPaymentMeans element" do
      expect(xml).to include("ram:SpecifiedTradeSettlementPaymentMeans")
    end

    it "includes TypeCode 30" do
      expect(xml).to include("<ram:TypeCode>30</ram:TypeCode>")
    end

    it "includes IBAN" do
      expect(xml).to include("FR7630006000011234567890189")
    end

    it "includes BIC" do
      expect(xml).to include("BNPAFRPP")
    end

    it "omits BIC element when bic is nil" do
      inv_no_bic = Einvoicing::Invoice.new(
        invoice_number:     "INV-2024-001",
        issue_date:         Date.new(2024, 1, 15),
        seller:             Fixtures.seller,
        buyer:              Fixtures.buyer,
        lines:              [ Fixtures.line ],
        payment_means_code: 30,
        iban:               "FR7630006000011234567890189"
      )
      xml_no_bic = described_class.generate(inv_no_bic)
      expect(xml_no_bic).not_to include("ram:BICID")
    end
  end

  context "without payment means" do
    it "omits SpecifiedTradeSettlementPaymentMeans entirely" do
      expect(xml).not_to include("SpecifiedTradeSettlementPaymentMeans")
    end
  end

  context "with multiple VAT rates" do
    let(:lines) do
      [
        Einvoicing::LineItem.new(description: "Service A", quantity: 1, unit_price: 100.0, vat_rate: 0.20),
        Einvoicing::LineItem.new(description: "Service B", quantity: 1, unit_price: 100.0, vat_rate: 0.10)
      ]
    end
    let(:invoice) { Fixtures.invoice(lines: lines) }

    it "generates two ApplicableTradeTax entries in settlement" do
      # 2 line-level + 2 settlement-level = 4 ApplicableTradeTax blocks total
      count = xml.scan("<ram:ApplicableTradeTax>").length
      expect(count).to eq(4)
    end
  end

  context "credit note" do
    let(:invoice) do
      Einvoicing::Invoice.new(
        invoice_number:          "AVOIR-2024-001",
        issue_date:              Date.new(2024, 4, 1),
        seller:                  Fixtures.seller,
        buyer:                   Fixtures.buyer,
        lines:                   [ Fixtures.line ],
        document_type:           :credit_note,
        original_invoice_number: "FAC-2024-0042",
        original_invoice_date:   Date.new(2024, 3, 15)
      )
    end

    it "uses TypeCode 381" do
      expect(xml).to include("<ram:TypeCode>381</ram:TypeCode>")
    end

    it "includes IncludedNote referencing original invoice" do
      expect(xml).to include("Avoir sur facture FAC-2024-0042")
      expect(xml).to include("15/03/2024")
    end

    it "is well-formed XML" do
      require "rexml/document"
      doc = REXML::Document.new(xml)
      expect(doc.root).not_to be_nil
    end
  end

  it "generates XSD-valid CII XML for EN16931 profile" do
    errors = validate_against_xsd(xml, "EN16931")
    expect(errors).to be_empty, "XSD errors: #{errors.map(&:message).join(', ')}"
  end
end
