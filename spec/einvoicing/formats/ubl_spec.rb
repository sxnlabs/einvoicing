# frozen_string_literal: true

require "spec_helper"

RSpec.describe Einvoicing::Formats::UBL do
  let(:invoice) { Fixtures.invoice }
  let(:xml)     { described_class.generate(invoice) }

  it "generates a non-empty XML string" do
    expect(xml).to be_a(String)
    expect(xml).not_to be_empty
  end

  it "starts with XML declaration" do
    expect(xml).to start_with('<?xml version="1.0" encoding="UTF-8"?>')
  end

  it "includes the Invoice root element" do
    expect(xml).to include("<Invoice")
  end

  it "includes UBL namespace" do
    expect(xml).to include("urn:oasis:names:specification:ubl:schema:xsd:Invoice-2")
  end

  it "includes Peppol BIS customization ID" do
    expect(xml).to include("urn:cen.eu:en16931:2017#compliant#urn:fdc:peppol.eu:2017:poacc:billing:3.0")
  end

  it "includes the invoice number" do
    expect(xml).to include("INV-2024-001")
  end

  it "includes invoice type code 380" do
    expect(xml).to include("<cbc:InvoiceTypeCode>380</cbc:InvoiceTypeCode>")
  end

  it "includes issue date in ISO format" do
    expect(xml).to include("<cbc:IssueDate>2024-01-15</cbc:IssueDate>")
  end

  it "includes due date in ISO format" do
    expect(xml).to include("<cbc:DueDate>2024-02-15</cbc:DueDate>")
  end

  it "includes seller party" do
    expect(xml).to include("Acme SAS")
    expect(xml).to include("cac:AccountingSupplierParty")
  end

  it "includes buyer party" do
    expect(xml).to include("Client SA")
    expect(xml).to include("cac:AccountingCustomerParty")
  end

  it "includes seller VAT number" do
    expect(xml).to include("FR83356000000")
  end

  it "includes seller SIREN" do
    expect(xml).to include("356000000")
  end

  it "includes TaxTotal" do
    expect(xml).to include("cac:TaxTotal")
    expect(xml).to include("200.00")
  end

  it "includes LegalMonetaryTotal" do
    expect(xml).to include("cac:LegalMonetaryTotal")
    expect(xml).to include("1000.00")  # net
    expect(xml).to include("1200.00")  # gross
  end

  it "includes InvoiceLine" do
    expect(xml).to include("cac:InvoiceLine")
    expect(xml).to include("Software consulting")
  end

  it "includes currency on monetary amounts" do
    expect(xml).to include('currencyID="EUR"')
  end

  it "is well-formed XML" do
    require "rexml/document"
    doc = REXML::Document.new(xml)
    expect(doc.root).not_to be_nil
    expect(doc.root.name).to eq("Invoice")
  end
end
