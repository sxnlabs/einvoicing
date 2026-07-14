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

    it "includes cac:PaymentMeans element" do
      expect(xml).to include("cac:PaymentMeans")
    end

    it "includes PaymentMeansCode 30" do
      expect(xml).to include("<cbc:PaymentMeansCode>30</cbc:PaymentMeansCode>")
    end

    it "includes IBAN" do
      expect(xml).to include("FR7630006000011234567890189")
    end

    it "includes BIC in FinancialInstitutionBranch" do
      expect(xml).to include("BNPAFRPP")
      expect(xml).to include("cac:FinancialInstitutionBranch")
    end

    it "omits BIC branch when bic is nil" do
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
      expect(xml_no_bic).not_to include("FinancialInstitutionBranch")
    end
  end

  context "without payment means" do
    it "omits cac:PaymentMeans entirely" do
      expect(xml).not_to include("cac:PaymentMeans")
    end
  end

  context "with prepaid_amount (retenue de garantie, BT-113)" do
    let(:invoice) do
      Einvoicing::Invoice.new(
        invoice_number: "INV-2024-001",
        issue_date:     Date.new(2024, 1, 15),
        seller:         Fixtures.seller,
        buyer:          Fixtures.buyer,
        lines:          [ Fixtures.line ],
        prepaid_amount: BigDecimal("100")
      )
    end

    it "includes cbc:PrepaidAmount immediately before cbc:PayableAmount" do
      expect(xml).to include('<cbc:PrepaidAmount currencyID="EUR">100.00</cbc:PrepaidAmount>')
      prepaid_index = xml.index("<cbc:PrepaidAmount")
      payable_index  = xml.index("<cbc:PayableAmount")
      expect(xml[prepaid_index...payable_index])
        .to match(%r{\A<cbc:PrepaidAmount currencyID="EUR">100\.00</cbc:PrepaidAmount>\s*\z})
    end

    it "computes PayableAmount as TaxInclusiveAmount minus PrepaidAmount (BR-CO-16)" do
      expect(xml).to include('<cbc:TaxInclusiveAmount currencyID="EUR">1200.00</cbc:TaxInclusiveAmount>')
      expect(xml).to include('<cbc:PayableAmount currencyID="EUR">1100.00</cbc:PayableAmount>')
    end
  end

  context "without prepaid_amount" do
    it "omits cbc:PrepaidAmount entirely" do
      expect(xml).not_to include("PrepaidAmount")
    end
  end

  it "always emits BuyerReference (falls back to invoice_number)" do
    inv = Einvoicing::Invoice.new(
      invoice_number: "INV-2024-001",
      issue_date:     Date.new(2024, 1, 15),
      seller:         Fixtures.seller,
      buyer:          Fixtures.buyer,
      lines:          [ Fixtures.line ]
    )
    xml_no_ref = described_class.generate(inv)
    expect(xml_no_ref).to include("<cbc:BuyerReference>INV-2024-001</cbc:BuyerReference>")
  end

  it "emits TaxCurrencyCode when tax_currency is set" do
    inv = Einvoicing::Invoice.new(
      invoice_number: "INV-2024-001",
      issue_date:     Date.new(2024, 1, 15),
      seller:         Fixtures.seller,
      buyer:          Fixtures.buyer,
      lines:          [ Fixtures.line ],
      currency:       "USD",
      tax_currency:   "EUR"
    )
    xml_with_tax_currency = described_class.generate(inv)
    expect(xml_with_tax_currency).to include("<cbc:TaxCurrencyCode>EUR</cbc:TaxCurrencyCode>")
  end

  it "omits TaxCurrencyCode when tax_currency is nil" do
    expect(xml).not_to include("TaxCurrencyCode")
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

    it "uses CreditNote as root element" do
      expect(xml).to include("<CreditNote")
      expect(xml).not_to include("<Invoice")
    end

    it "uses CreditNote-2 namespace" do
      expect(xml).to include("urn:oasis:names:specification:ubl:schema:xsd:CreditNote-2")
    end

    it "uses InvoiceTypeCode 381" do
      expect(xml).to include("<cbc:InvoiceTypeCode>381</cbc:InvoiceTypeCode>")
    end

    it "includes BillingReference to original invoice" do
      expect(xml).to include("cac:BillingReference")
      expect(xml).to include("FAC-2024-0042")
      expect(xml).to include("2024-03-15")
    end

    it "is well-formed XML" do
      require "rexml/document"
      doc = REXML::Document.new(xml)
      expect(doc.root).not_to be_nil
      expect(doc.root.name).to eq("CreditNote")
    end
  end
end
