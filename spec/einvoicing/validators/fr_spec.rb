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
        lines: [ Fixtures.line ]
      )
      errors = described_class.validate(inv)
      expect(errors).to include(a_hash_including(field: :invoice_number, error: :number_missing))
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
        lines: [ Fixtures.line ]
      )
      errors = described_class.validate(inv)
      expect(errors).to include(a_hash_including(field: :seller_siren, error: :siren_invalid))
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
        lines: [ Fixtures.line ]
      )
      errors = described_class.validate(inv)
      expect(errors).to include(a_hash_including(field: :seller_vat_number, error: :vat_number_invalid))
    end

    it "reports non-standard VAT rate" do
      inv = Einvoicing::Invoice.new(
        invoice_number: "INV-001",
        issue_date: Date.today,
        seller: Fixtures.seller,
        buyer: Fixtures.buyer,
        lines: [ Einvoicing::LineItem.new(description: "X", quantity: 1, unit_price: 100.0, vat_rate: 0.15) ]
      )
      errors = described_class.validate(inv)
      expect(errors).to include(a_hash_including(field: :line_1_vat_rate, error: :vat_rate_invalid))
    end
  end

  describe ".validate!" do
    it "raises ValidationError for invalid invoices" do
      inv = Einvoicing::Invoice.new(
        invoice_number: "",
        issue_date: Date.today,
        seller: Fixtures.seller,
        buyer: Fixtures.buyer,
        lines: [ Fixtures.line ]
      )
      expect { described_class.validate!(inv) }
        .to raise_error(Einvoicing::Validators::ValidationError)
    end

    it "returns true for valid invoices" do
      expect(described_class.validate!(Fixtures.invoice)).to be true
    end
  end

  describe ".valid_iban?" do
    it "accepts a valid French IBAN" do
      expect(described_class.valid_iban?("FR7630006000011234567890189")).to be true
    end

    it "rejects an IBAN with wrong checksum" do
      expect(described_class.valid_iban?("FR7630006000011234567890188")).to be false
    end

    it "rejects an IBAN that is too short" do
      expect(described_class.valid_iban?("FR76")).to be false
    end

    it "rejects a non-IBAN string" do
      expect(described_class.valid_iban?("not-an-iban")).to be false
    end
  end

  describe ".valid_bic?" do
    it "accepts an 8-character BIC" do
      expect(described_class.valid_bic?("BNPAFRPP")).to be true
    end

    it "accepts an 11-character BIC" do
      expect(described_class.valid_bic?("BNPAFRPPXXX")).to be true
    end

    it "rejects a BIC with wrong length" do
      expect(described_class.valid_bic?("BNPA")).to be false
    end

    it "rejects a BIC with lowercase letters" do
      expect(described_class.valid_bic?("bnpafrpp")).to be false
    end
  end

  describe "credit note validation" do
    it "reports missing original_invoice_number for credit notes" do
      inv = Einvoicing::Invoice.new(
        invoice_number: "AVOIR-001",
        issue_date:     Date.today,
        seller:         Fixtures.seller,
        buyer:          Fixtures.buyer,
        lines:          [ Fixtures.line ],
        document_type:  :credit_note
      )
      errors = described_class.validate(inv)
      expect(errors).to include(a_hash_including(
        field: :original_invoice_number,
        error: :original_invoice_number_missing
      ))
    end

    it "accepts a credit note with original_invoice_number" do
      inv = Einvoicing::Invoice.new(
        invoice_number:          "AVOIR-001",
        issue_date:              Date.today,
        seller:                  Fixtures.seller,
        buyer:                   Fixtures.buyer,
        lines:                   [ Fixtures.line ],
        document_type:           :credit_note,
        original_invoice_number: "FAC-2024-0042"
      )
      errors = described_class.validate(inv)
      expect(errors.map { |e| e[:error] }).not_to include(:original_invoice_number_missing)
    end
  end

  describe "IBAN/BIC validation" do
    it "reports invalid IBAN" do
      inv = Einvoicing::Invoice.new(
        invoice_number: "INV-001",
        issue_date:     Date.today,
        seller:         Fixtures.seller,
        buyer:          Fixtures.buyer,
        lines:          [ Fixtures.line ],
        iban:           "FR0000000000000000000000000"  # bad checksum
      )
      errors = described_class.validate(inv)
      expect(errors).to include(a_hash_including(field: :iban, error: :iban_invalid))
    end

    it "accepts a valid IBAN" do
      inv = Einvoicing::Invoice.new(
        invoice_number: "INV-001",
        issue_date:     Date.today,
        seller:         Fixtures.seller,
        buyer:          Fixtures.buyer,
        lines:          [ Fixtures.line ],
        iban:           "FR7630006000011234567890189"
      )
      errors = described_class.validate(inv)
      expect(errors.map { |e| e[:error] }).not_to include(:iban_invalid)
    end

    it "reports invalid BIC" do
      inv = Einvoicing::Invoice.new(
        invoice_number: "INV-001",
        issue_date:     Date.today,
        seller:         Fixtures.seller,
        buyer:          Fixtures.buyer,
        lines:          [ Fixtures.line ],
        bic:            "bad"
      )
      errors = described_class.validate(inv)
      expect(errors).to include(a_hash_including(field: :bic, error: :bic_invalid))
    end
  end
end
