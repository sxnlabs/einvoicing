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

  describe "BuyerReference (BT-10)" do
    it "falls back to the invoice number rather than emitting an empty element" do
      no_reference = Fixtures.invoice.with(payment_reference: nil)

      expect(described_class.generate(no_reference))
        .to include("<ram:BuyerReference>#{no_reference.invoice_number}</ram:BuyerReference>")
    end

    it "matches what UBL emits for the same invoice" do
      no_reference = Fixtures.invoice.with(payment_reference: nil)
      cii = described_class.generate(no_reference)[%r{<ram:BuyerReference>([^<]*)</ram:BuyerReference>}, 1]
      ubl = Einvoicing::Formats::UBL.generate(no_reference)[%r{<cbc:BuyerReference>([^<]*)</cbc:BuyerReference>}, 1]

      expect(cii).to eq(ubl)
    end

    it "keeps the payment reference when one is given" do
      expect(xml).to include("<ram:BuyerReference>#{invoice.payment_reference}</ram:BuyerReference>")
    end
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

  # ISO 6523: 0002 is SIRENE — the nine-digit SIREN. A fourteen-digit SIRET
  # announced under it is what a Plateforme Agréée refuses the document for,
  # and our own XSD does not catch it because both are just strings.
  context "when a party carries a SIRET" do
    let(:seller_with_siret) do
      Einvoicing::Party.new(name: "Acme SAS", siret: "35600000000048",
                            vat_number: "FR39356000000", country_code: "FR")
    end
    let(:siret_xml) do
      described_class.generate(invoice.with(seller: seller_with_siret))
    end

    it "announces it as 0009, not as 0002" do
      expect(siret_xml).to include('schemeID="0009"')
      expect(siret_xml).to include("35600000000048")
    end

    it "still announces a SIREN-only party as 0002" do
      expect(siret_xml).to include('schemeID="0002"')
    end

    it "keeps the literal SIRET scheme for Chorus Pro, which predates the codelist" do
      chorus = described_class.generate(invoice.with(seller: seller_with_siret), profile: :chorus_pro)

      expect(chorus).to include('schemeID="SIRET"')
      expect(chorus).not_to include('schemeID="0009"')
    end
  end

  it "includes seller VAT number" do
    expect(xml).to include("FR39356000000")
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

  context "with prepaid_amount (retenue de garantie, BT-113)" do
    let(:invoice) do
      Einvoicing::Invoice.new(
        invoice_number:    "INV-2024-001",
        issue_date:        Date.new(2024, 1, 15),
        due_date:          Date.new(2024, 2, 15),
        seller:            Fixtures.seller,
        buyer:             Fixtures.buyer,
        lines:             [ Fixtures.line ],
        payment_reference: "PO-2024-001",
        prepaid_amount:    BigDecimal("100")
      )
    end

    it "includes TotalPrepaidAmount immediately before DuePayableAmount" do
      expect(xml).to include("<ram:TotalPrepaidAmount>100.00</ram:TotalPrepaidAmount>")
      prepaid_index = xml.index("<ram:TotalPrepaidAmount>")
      due_index      = xml.index("<ram:DuePayableAmount>")
      expect(xml[prepaid_index...due_index]).to match(/\A<ram:TotalPrepaidAmount>100\.00<\/ram:TotalPrepaidAmount>\s*\z/)
    end

    it "computes DuePayableAmount as GrandTotal minus TotalPrepaidAmount (BR-CO-16)" do
      expect(xml).to include("<ram:GrandTotalAmount>1200.00</ram:GrandTotalAmount>")
      expect(xml).to include("<ram:DuePayableAmount>1100.00</ram:DuePayableAmount>")
    end

    it "generates XSD-valid CII XML with TotalPrepaidAmount present" do
      errors = validate_against_xsd(xml, "EN16931")
      expect(errors).to be_empty, "XSD errors: #{errors.map(&:message).join(', ')}"
    end
  end

  context "without prepaid_amount" do
    it "omits TotalPrepaidAmount entirely" do
      expect(xml).not_to include("TotalPrepaidAmount")
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

    it "emits the preceding invoice reference as EN 16931 BG-3" do
      require "nokogiri"
      document = Nokogiri::XML(xml)
      namespaces = {
        "ram" => described_class::RAM_NS,
        "qdt" => described_class::QDT_NS
      }

      settlement = document.at_xpath(
        "//ram:ApplicableHeaderTradeSettlement",
        namespaces
      )
      reference = settlement.at_xpath("./ram:InvoiceReferencedDocument", namespaces)

      expect(reference.at_xpath("./ram:IssuerAssignedID", namespaces).text).to eq("FAC-2024-0042")
      date = reference.at_xpath("./ram:FormattedIssueDateTime/qdt:DateTimeString", namespaces)
      expect(date.text).to eq("20240315")
      expect(date["format"]).to eq("102")
    end

    it "preserves the legacy human-readable reference note" do
      require "nokogiri"
      document = Nokogiri::XML(xml)
      notes = document.xpath("//ram:IncludedNote/ram:Content", "ram" => described_class::RAM_NS)

      expect(notes.map(&:text)).to eq([
        "Credit note for invoice FAC-2024-0042 dated 15/03/2024"
      ])
    end

    it "places BG-3 after the header monetary summation as required by the CII schema" do
      require "nokogiri"
      document = Nokogiri::XML(xml)
      settlement = document.at_xpath(
        "//ram:ApplicableHeaderTradeSettlement",
        "ram" => described_class::RAM_NS
      )

      child_names = settlement.element_children.map(&:name)
      expect(child_names.index("InvoiceReferencedDocument")).to be > child_names.index(
        "SpecifiedTradeSettlementHeaderMonetarySummation"
      )
    end

    it "is well-formed XML" do
      require "rexml/document"
      doc = REXML::Document.new(xml)
      expect(doc.root).not_to be_nil
    end

    it "is XSD-valid for the EN16931 profile" do
      errors = validate_against_xsd(xml, "EN16931")
      expect(errors).to be_empty, "XSD errors: #{errors.map(&:message).join(', ')}"
    end

    context "without the preceding invoice date" do
      let(:invoice) do
        Einvoicing::Invoice.new(
          invoice_number:          "AVOIR-2024-001",
          issue_date:              Date.new(2024, 4, 1),
          seller:                  Fixtures.seller,
          buyer:                   Fixtures.buyer,
          lines:                   [ Fixtures.line ],
          document_type:           :credit_note,
          original_invoice_number: "FAC-2024-0042"
        )
      end

      it "emits the required BT-25 without optional BT-26" do
        require "nokogiri"
        document = Nokogiri::XML(xml)
        namespaces = { "ram" => described_class::RAM_NS }
        reference = document.at_xpath(
          "//ram:ApplicableHeaderTradeSettlement/ram:InvoiceReferencedDocument",
          namespaces
        )

        expect(reference.at_xpath("./ram:IssuerAssignedID", namespaces).text).to eq("FAC-2024-0042")
        expect(reference.at_xpath("./ram:FormattedIssueDateTime", namespaces)).to be_nil
      end
    end

    context "with an explicit invoice note" do
      let(:invoice) do
        super().with(note: "Contract cancellation")
      end

      it "emits only the explicit note while retaining structured BG-3" do
        require "nokogiri"
        document = Nokogiri::XML(xml)
        namespaces = { "ram" => described_class::RAM_NS }
        notes = document.xpath("//ram:IncludedNote/ram:Content", namespaces)

        expect(notes.map(&:text)).to eq([ "Contract cancellation" ])
        expect(document.at_xpath(
          "//ram:ApplicableHeaderTradeSettlement/ram:InvoiceReferencedDocument/ram:IssuerAssignedID",
          namespaces
        ).text).to eq("FAC-2024-0042")
      end

      it "remains XSD-valid" do
        errors = validate_against_xsd(xml, "EN16931")
        expect(errors).to be_empty, "XSD errors: #{errors.map(&:message).join(', ')}"
      end
    end

    context "with a blank invoice note" do
      let(:invoice) do
        super().with(note: "  ")
      end

      it "falls back to the legacy human-readable reference note" do
        expect(xml).to include(
          "<ram:Content>Credit note for invoice FAC-2024-0042 dated 15/03/2024</ram:Content>"
        )
      end
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

    let(:namespaces) { { "ram" => described_class::RAM_NS, "udt" => described_class::UDT_NS } }
    let(:document) do
      require "nokogiri"
      Nokogiri::XML(xml)
    end

    it "emits the allowance with a false charge indicator" do
      node = document.xpath("//ram:SpecifiedTradeAllowanceCharge", namespaces).first

      expect(node.at_xpath("./ram:ChargeIndicator/udt:Indicator", namespaces).text).to eq("false")
      expect(node.at_xpath("./ram:CalculationPercent", namespaces).text).to eq("10.00")
      expect(node.at_xpath("./ram:BasisAmount", namespaces).text).to eq("1000.00")
      expect(node.at_xpath("./ram:ActualAmount", namespaces).text).to eq("100.00")
      expect(node.at_xpath("./ram:ReasonCode", namespaces).text).to eq("95")
      expect(node.at_xpath("./ram:Reason", namespaces).text).to eq("Remise commerciale")
      expect(node.at_xpath("./ram:CategoryTradeTax/ram:CategoryCode", namespaces).text).to eq("S")
      expect(node.at_xpath("./ram:CategoryTradeTax/ram:RateApplicablePercent", namespaces).text).to eq("20.00")
    end

    it "emits the charge with a true charge indicator" do
      node = document.xpath("//ram:SpecifiedTradeAllowanceCharge", namespaces).last

      expect(node.at_xpath("./ram:ChargeIndicator/udt:Indicator", namespaces).text).to eq("true")
      expect(node.at_xpath("./ram:ActualAmount", namespaces).text).to eq("50.00")
      expect(node.at_xpath("./ram:Reason", namespaces).text).to eq("Frais de port")
    end

    it "reports the adjusted monetary summation" do
      summation = document.at_xpath(
        "//ram:SpecifiedTradeSettlementHeaderMonetarySummation", namespaces
      )

      expect(summation.at_xpath("./ram:LineTotalAmount", namespaces).text).to eq("1000.00")
      expect(summation.at_xpath("./ram:ChargeTotalAmount", namespaces).text).to eq("50.00")
      expect(summation.at_xpath("./ram:AllowanceTotalAmount", namespaces).text).to eq("100.00")
      expect(summation.at_xpath("./ram:TaxBasisTotalAmount", namespaces).text).to eq("950.00")
      expect(summation.at_xpath("./ram:TaxTotalAmount", namespaces).text).to eq("190.00")
      expect(summation.at_xpath("./ram:GrandTotalAmount", namespaces).text).to eq("1140.00")
      expect(summation.at_xpath("./ram:DuePayableAmount", namespaces).text).to eq("1140.00")
    end

    it "omits the allowance and charge totals when there are none" do
      plain = described_class.generate(Fixtures.invoice)

      expect(plain).not_to include("ram:AllowanceTotalAmount")
      expect(plain).not_to include("ram:ChargeTotalAmount")
    end

    it "remains XSD-valid" do
      errors = validate_against_xsd(xml, "EN16931")
      expect(errors).to be_empty, "XSD errors: #{errors.map(&:message).join(', ')}"
    end
  end

  it "generates XSD-valid CII XML for EN16931 profile" do
    errors = validate_against_xsd(xml, "EN16931")
    expect(errors).to be_empty, "XSD errors: #{errors.map(&:message).join(', ')}"
  end

  context "with profile: :chorus_pro" do
    let(:seller_siret) do
      Einvoicing::Party.new(
        name:         "Fournisseur Test",
        street:       "1 rue de la Paix",
        city:         "Paris",
        postal_code:  "75001",
        country_code: "FR",
        siren:        "370647042",
        siret:        "37064704200008",
        vat_number:   "FR68370647042"
      )
    end

    let(:xml) do
      described_class.generate(
        Einvoicing::Invoice.new(
          invoice_number:     "CPRO-001",
          issue_date:         Date.new(2024, 1, 15),
          seller:             seller_siret,
          buyer:              Fixtures.buyer,
          lines:              [ Fixtures.line ],
          payment_means_code: 30
        ),
        profile: :chorus_pro
      )
    end

    it "uses schemeID SIRET for seller with SIRET" do
      expect(xml).to include('schemeID="SIRET"')
      expect(xml).to include("37064704200008")
    end

    it "uses schemeID 0002 for buyer with SIREN only" do
      expect(xml).to include('schemeID="0002"')
      expect(xml).to include("552032534")
    end
  end
end
