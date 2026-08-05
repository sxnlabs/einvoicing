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
    expect(xml).to include("FR39356000000")
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

  describe "document-level allowances and charges (BG-20 / BG-21)" do
    let(:invoice) do
      Fixtures.invoice.with(
        allowances: [
          Einvoicing::AllowanceCharge.new(amount: "100.00", vat_rate: 0.20,
                                          reason: "Remise commerciale", reason_code: "95",
                                          base_amount: "1000.00", percentage: 10)
        ],
        charges: [
          Einvoicing::AllowanceCharge.new(amount: "50.00", vat_rate: 0.20,
                                          reason: "Frais de port", reason_code: "FC")
        ]
      )
    end

    let(:namespaces) { { "cac" => described_class::CAC_NS, "cbc" => described_class::CBC_NS } }
    let(:document) do
      require "nokogiri"
      Nokogiri::XML(xml)
    end

    it "emits the allowance with a false charge indicator" do
      node = document.xpath("//cac:AllowanceCharge", namespaces).first

      expect(node.at_xpath("./cbc:ChargeIndicator", namespaces).text).to eq("false")
      expect(node.at_xpath("./cbc:AllowanceChargeReasonCode", namespaces).text).to eq("95")
      expect(node.at_xpath("./cbc:AllowanceChargeReason", namespaces).text).to eq("Remise commerciale")
      expect(node.at_xpath("./cbc:MultiplierFactorNumeric", namespaces).text).to eq("10.00")
      expect(node.at_xpath("./cbc:Amount", namespaces).text).to eq("100.00")
      expect(node.at_xpath("./cbc:BaseAmount", namespaces).text).to eq("1000.00")
      expect(node.at_xpath("./cac:TaxCategory/cbc:ID", namespaces).text).to eq("S")
      expect(node.at_xpath("./cac:TaxCategory/cbc:Percent", namespaces).text).to eq("20.00")
    end

    it "emits the charge with a true charge indicator" do
      node = document.xpath("//cac:AllowanceCharge", namespaces).last

      expect(node.at_xpath("./cbc:ChargeIndicator", namespaces).text).to eq("true")
      expect(node.at_xpath("./cbc:Amount", namespaces).text).to eq("50.00")
      expect(node.at_xpath("./cbc:AllowanceChargeReason", namespaces).text).to eq("Frais de port")
    end

    it "reports the adjusted legal monetary total" do
      total = document.at_xpath("//cac:LegalMonetaryTotal", namespaces)

      expect(total.at_xpath("./cbc:LineExtensionAmount", namespaces).text).to eq("1000.00")
      expect(total.at_xpath("./cbc:TaxExclusiveAmount", namespaces).text).to eq("950.00")
      expect(total.at_xpath("./cbc:TaxInclusiveAmount", namespaces).text).to eq("1140.00")
      expect(total.at_xpath("./cbc:AllowanceTotalAmount", namespaces).text).to eq("100.00")
      expect(total.at_xpath("./cbc:ChargeTotalAmount", namespaces).text).to eq("50.00")
      expect(total.at_xpath("./cbc:PayableAmount", namespaces).text).to eq("1140.00")
    end

    it "adjusts the tax subtotal for the matching rate" do
      subtotal = document.at_xpath("//cac:TaxTotal/cac:TaxSubtotal", namespaces)

      expect(subtotal.at_xpath("./cbc:TaxableAmount", namespaces).text).to eq("950.00")
      expect(subtotal.at_xpath("./cbc:TaxAmount", namespaces).text).to eq("190.00")
    end

    it "omits the allowance and charge totals when there are none" do
      plain = described_class.generate(Fixtures.invoice)

      expect(plain).not_to include("cbc:AllowanceTotalAmount")
      expect(plain).not_to include("cbc:ChargeTotalAmount")
    end

    it "places AllowanceCharge before TaxTotal (UBL element order)" do
      expect(xml.index("cac:AllowanceCharge")).to be < xml.index("cac:TaxTotal")
    end
  end
end
