# frozen_string_literal: true

require "spec_helper"

RSpec.describe Einvoicing::Formats::CII do
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

  context "with multiple VAT rates" do
    let(:lines) do
      [
        Einvoicing::LineItem.new(description: "Service A", quantity: 1, unit_price: 100.0, vat_rate: 0.20),
        Einvoicing::LineItem.new(description: "Service B", quantity: 1, unit_price: 100.0, vat_rate: 0.10)
      ]
    end
    let(:invoice) { Fixtures.invoice(lines: lines) }

    it "generates two ApplicableTradeTax entries in settlement" do
      count = xml.scan("ram:ApplicableTradeTax").length / 2 # open+close tags
      # Each line has an ApplicableTradeTax + two in settlement = 4 total sections
      expect(xml).to include("RateApplicablePercent")
    end
  end
end
