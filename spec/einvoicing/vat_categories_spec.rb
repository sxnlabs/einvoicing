# frozen_string_literal: true

require "spec_helper"
require "support/schema_validation"

RSpec.describe Einvoicing::Tax do
  include SchemaValidation

  def invoice_with(lines:, **overrides)
    Einvoicing::Invoice.new(
      invoice_number: "INV-2026-001",
      issue_date:     Date.new(2026, 1, 15),
      due_date:       Date.new(2026, 2, 15),
      seller:         Fixtures.seller,
      buyer:          Fixtures.buyer,
      lines:          lines,
      **overrides
    )
  end

  def line(category:, rate: 0, **rest)
    Einvoicing::LineItem.new(description: "Service", quantity: 1, unit_price: 1000.00,
                             vat_rate: rate, category: category, **rest)
  end

  describe "category codes" do
    it "maps every EN 16931 category to its BT-118 code" do
      expect(described_class::CATEGORY_CODES).to eq(
        standard: "S", zero_rated: "Z", exempt: "E", reverse_charge: "AE",
        intra_community: "K", export: "G", not_subject: "O"
      )
    end

    it "infers S or Z from the rate when no category is given" do
      expect(described_class.category_code_for(rate: 0.20)).to eq("S")
      expect(described_class.category_code_for(rate: 0)).to eq("Z")
    end

    it "raises on an unknown category rather than silently emitting S" do
      expect { described_class.category_code_for(rate: 0, category: :made_up) }
        .to raise_error(ArgumentError, /made_up/)
    end

    it "fills BT-120/BT-121 from the VATEX code list for reverse charge" do
      tax = described_class.new(rate: 0, taxable_amount: 100, tax_amount: 0,
                                category: :reverse_charge)
      expect(tax.exemption_reason_code).to eq("VATEX-EU-AE")
      expect(tax.exemption_reason).to eq("Reverse charge")
      expect(tax).to be_exemption_required
    end

    it "leaves BT-120/BT-121 to the caller for a plain exemption" do
      tax = described_class.new(rate: 0, taxable_amount: 100, tax_amount: 0, category: :exempt)
      expect(tax.exemption_reason_code).to be_nil
      expect(tax).to be_exemption_required
    end

    it "never attaches an exemption reason to a zero-rated or standard line" do
      %i[zero_rated standard].each do |category|
        tax = described_class.new(rate: 0, taxable_amount: 100, tax_amount: 0, category: category)
        expect(tax).not_to be_exemption_required
      end
    end

    it "bills 0 % for every exempt-like category whatever rate is passed in" do
      %i[zero_rated exempt reverse_charge intra_community export not_subject].each do |category|
        expect(described_class.effective_rate(rate: 0.20, category: category)).to eq(0)
      end
      expect(described_class.effective_rate(rate: 0.20, category: :standard)).to eq(BigDecimal("0.20"))
    end
  end

  describe "CII output" do
    it "emits ExemptionReason and ExemptionReasonCode for a reverse charge" do
      xml = Einvoicing::Formats::CII.generate(invoice_with(lines: [ line(category: :reverse_charge) ]))
      expect(xml).to include("<ram:CategoryCode>AE</ram:CategoryCode>")
      expect(xml).to include("<ram:ExemptionReason>Reverse charge</ram:ExemptionReason>")
      expect(xml).to include("<ram:ExemptionReasonCode>VATEX-EU-AE</ram:ExemptionReasonCode>")
    end

    it "carries a caller-supplied reason for the French art. 293 B franchise" do
      franchise = line(category: :exempt,
                       exemption_reason: "TVA non applicable, art. 293 B du CGI",
                       exemption_reason_code: Einvoicing::Tax::VATEX_FR_FRANCHISE)
      xml = Einvoicing::Formats::CII.generate(invoice_with(lines: [ franchise ]))
      expect(xml).to include("<ram:CategoryCode>E</ram:CategoryCode>")
      expect(xml).to include("<ram:ExemptionReason>TVA non applicable, art. 293 B du CGI</ram:ExemptionReason>")
      expect(xml).to include("<ram:ExemptionReasonCode>VATEX-FR-FRANCHISE</ram:ExemptionReasonCode>")
    end

    it "omits BT-120/BT-121 on a standard-rated invoice (BR-Z-10 and friends)" do
      xml = Einvoicing::Formats::CII.generate(Fixtures.invoice)
      expect(xml).not_to include("ExemptionReason")
    end

    it "stays schema-valid with an exemption reason present" do
      xml = Einvoicing::Formats::CII.generate(invoice_with(lines: [ line(category: :intra_community) ]))
      expect(validate_against_xsd(xml, "EN16931")).to be_empty
    end
  end

  describe "UBL output" do
    it "emits TaxExemptionReasonCode before TaxExemptionReason inside TaxCategory" do
      xml = Einvoicing::Formats::UBL.generate(invoice_with(lines: [ line(category: :export) ]))
      expect(xml).to match(
        %r{<cbc:TaxExemptionReasonCode>VATEX-EU-G</cbc:TaxExemptionReasonCode>\s*
           <cbc:TaxExemptionReason>Export\ outside\ the\ EU</cbc:TaxExemptionReason>}x
      )
    end
  end

  describe "FR validator" do
    it "rejects an exempt breakdown with no reason at all" do
      errors = Einvoicing::Validators::FR.validate(invoice_with(lines: [ line(category: :exempt) ]))
      expect(errors).to include(a_hash_including(error: :exemption_reason_missing))
    end

    it "accepts a reverse charge, which carries the VATEX default" do
      errors = Einvoicing::Validators::FR.validate(
        invoice_with(lines: [ line(category: :reverse_charge) ])
      )
      expect(errors).to be_empty
    end
  end
end
