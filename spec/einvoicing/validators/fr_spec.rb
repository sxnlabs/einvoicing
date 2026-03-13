# frozen_string_literal: true

require "spec_helper"

RSpec.describe Einvoicing::Validators::FR do
  describe ".valid_siren?" do
    # Known valid SIRENs (Luhn-checked)
    it "accepts La Poste SIREN 356000000" do
      expect(described_class.valid_siren?("356000000")).to be true
    end

    it "accepts Renault SIREN 552032534" do
      expect(described_class.valid_siren?("552032534")).to be true
    end

    it "rejects a SIREN with wrong checksum" do
      expect(described_class.valid_siren?("356000001")).to be false
    end

    it "rejects a SIREN with wrong length" do
      expect(described_class.valid_siren?("12345")).to be false
    end

    it "rejects a non-numeric SIREN" do
      expect(described_class.valid_siren?("ABCDEFGHI")).to be false
    end
  end

  describe ".valid_siret?" do
    # La Poste SIRET: SIREN 356000000 + NIC 00048 = 35600000000048
    it "accepts a known valid SIRET" do
      expect(described_class.valid_siret?("35600000000048")).to be true
    end

    it "rejects a SIRET with wrong length" do
      expect(described_class.valid_siret?("12345")).to be false
    end

    it "rejects a SIRET with bad checksum" do
      expect(described_class.valid_siret?("35600000000049")).to be false
    end
  end

  describe ".valid_vat_number?" do
    it "accepts a valid French VAT number" do
      expect(described_class.valid_vat_number?("FR83356000000")).to be true
    end

    it "accepts VAT numbers with alphanumeric keys" do
      expect(described_class.valid_vat_number?("FRK7356000000")).to be true
    end

    it "rejects a VAT number without FR prefix" do
      expect(described_class.valid_vat_number?("DE12345678901")).to be false
    end

    it "rejects a VAT number with wrong format" do
      expect(described_class.valid_vat_number?("FR1234")).to be false
    end
  end

  describe ".valid_invoice_number?" do
    it "accepts alphanumeric invoice numbers" do
      expect(described_class.valid_invoice_number?("INV-2024-001")).to be true
    end

    it "accepts slashes" do
      expect(described_class.valid_invoice_number?("2024/01/001")).to be true
    end

    it "rejects empty string" do
      expect(described_class.valid_invoice_number?("")).to be false
    end

    it "rejects numbers over 35 chars" do
      expect(described_class.valid_invoice_number?("A" * 36)).to be false
    end
  end

  describe ".validate" do
    let(:invoice) { Fixtures.invoice }

    it "returns empty array for a valid invoice" do
      errors = described_class.validate(invoice)
      expect(errors).to be_empty
    end

    it "reports missing invoice number" do
      inv = Einvoicing::Invoice.new(
        invoice_number: "",
        issue_date: Date.today,
        seller: Fixtures.seller,
        buyer: Fixtures.buyer,
        lines: [Fixtures.line]
      )
      errors = described_class.validate(inv)
      expect(errors).to include(a_string_matching(/invoice number/i))
    end

    it "reports invalid seller SIREN" do
      bad_seller = Einvoicing::Party.new(
        name: "Bad Corp",
        siren: "000000001"  # fails Luhn
      )
      inv = Einvoicing::Invoice.new(
        invoice_number: "INV-001",
        issue_date: Date.today,
        seller: bad_seller,
        buyer: Fixtures.buyer,
        lines: [Fixtures.line]
      )
      errors = described_class.validate(inv)
      expect(errors).to include(a_string_matching(/SIREN/))
    end

    it "reports invalid VAT number format" do
      bad_seller = Einvoicing::Party.new(
        name: "Bad Corp",
        siren: "356000000",
        vat_number: "XX12345678901"
      )
      inv = Einvoicing::Invoice.new(
        invoice_number: "INV-001",
        issue_date: Date.today,
        seller: bad_seller,
        buyer: Fixtures.buyer,
        lines: [Fixtures.line]
      )
      errors = described_class.validate(inv)
      expect(errors).to include(a_string_matching(/VAT number/))
    end

    it "reports non-standard VAT rate" do
      inv = Einvoicing::Invoice.new(
        invoice_number: "INV-001",
        issue_date: Date.today,
        seller: Fixtures.seller,
        buyer: Fixtures.buyer,
        lines: [Einvoicing::LineItem.new(description: "X", quantity: 1, unit_price: 100.0, vat_rate: 0.15)]
      )
      errors = described_class.validate(inv)
      expect(errors).to include(a_string_matching(/vat_rate/i))
    end
  end

  describe ".validate!" do
    it "raises ValidationError for invalid invoices" do
      inv = Einvoicing::Invoice.new(
        invoice_number: "",
        issue_date: Date.today,
        seller: Fixtures.seller,
        buyer: Fixtures.buyer,
        lines: [Fixtures.line]
      )
      expect { described_class.validate!(inv) }
        .to raise_error(Einvoicing::Validators::ValidationError)
    end

    it "returns true for valid invoices" do
      expect(described_class.validate!(Fixtures.invoice)).to be true
    end
  end
end
