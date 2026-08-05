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
      expect(described_class.valid_vat_number?("FR39356000000")).to be true
    end

    it "accepts VAT numbers with alphanumeric keys" do
      expect(described_class.valid_vat_number?("FRK7356000000")).to be true
    end

    it "rejects a French VAT number whose check key does not match its SIREN" do
      # Right shape, right SIREN, wrong key: the key for 552032534 is 27.
      expect(described_class.valid_vat_number?("FR83552032534")).to be false
      expect(described_class.valid_vat_number?("FR27552032534")).to be true
    end

    it "checks the key against the SIREN, not against the digits alone" do
      # Same SIREN, every wrong numeric key must be refused.
      valid = "FR39356000000"
      wrong = (0..96).map { |k| format("FR%02d356000000", k) }.reject { |v| v == valid }

      expect(wrong.select { |v| described_class.valid_vat_number?(v) }).to be_empty
    end

    it "rejects a French VAT number carrying a SIREN that fails Luhn" do
      # 123456789 is not a real SIREN; no key can rescue it.
      expect(described_class.valid_vat_number?("FR32123456789")).to be false
    end

    it "does not apply the French key rule to another member state" do
      # DE811907980 has no such key; validating it as French would break it.
      expect(described_class.valid_vat_number?("DE811907980", country_code: "DE")).to be true
    end

    it "rejects a VAT number without FR prefix" do
      expect(described_class.valid_vat_number?("DE12345678901")).to be false
    end

    it "rejects a VAT number with wrong format" do
      expect(described_class.valid_vat_number?("FR1234")).to be false
    end

    it "accepts a counterparty's own member-state VAT number" do
      expect(described_class.valid_vat_number?("DE811907980", country_code: "DE")).to be true
      expect(described_class.valid_vat_number?("BE0123456789", country_code: "BE")).to be true
      expect(described_class.valid_vat_number?("NL123456789B01", country_code: "NL")).to be true
    end

    it "holds a party to its own country's pattern, not the number's prefix" do
      expect(described_class.valid_vat_number?("DE811907980", country_code: "FR")).to be false
    end

    it "rejects a malformed number from a known member state" do
      expect(described_class.valid_vat_number?("DE81190798", country_code: "DE")).to be false
    end

    it "does not flag an intra-Community buyer as invalid" do
      german_buyer = Einvoicing::Party.new(
        name: "Müller & Söhne GmbH", country_code: "DE", vat_number: "DE811907980"
      )
      inv = Einvoicing::Invoice.new(
        invoice_number: "INV-001", issue_date: Date.today,
        seller: Fixtures.seller, buyer: german_buyer, lines: [ Fixtures.line ]
      )
      expect(described_class.validate(inv))
        .not_to include(a_hash_including(field: :buyer_vat_number))
    end
  end

  describe ".valid_vat_rate?" do
    it "accepts the metropolitan rates" do
      [ 0, 0.021, 0.055, 0.10, 0.20 ].each do |rate|
        expect(described_class.valid_vat_rate?(rate)).to be(true), "expected #{rate} to be valid"
      end
    end

    it "accepts the DOM and Corsican rates that the usual shortlist drops" do
      [ 0.0105, 0.0175, 0.085, 0.009, 0.13 ].each do |rate|
        expect(described_class.valid_vat_rate?(rate)).to be(true), "expected #{rate} to be valid"
      end
    end

    it "still rejects an invented rate" do
      expect(described_class.valid_vat_rate?(0.15)).to be false
    end

    it "does not confuse 1.05 % with 1.75 %" do
      expect(described_class.valid_vat_rate?(0.011)).to be false
      expect(described_class.valid_vat_rate?(0.018)).to be false
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

  describe "prepaid_amount validation (BT-113)" do
    it "accepts a prepaid_amount within 0..gross_total" do
      inv = Einvoicing::Invoice.new(
        invoice_number: "INV-001",
        issue_date:     Date.today,
        seller:         Fixtures.seller,
        buyer:          Fixtures.buyer,
        lines:          [ Fixtures.line ],
        prepaid_amount: BigDecimal("100")
      )
      errors = described_class.validate(inv)
      expect(errors.map { |e| e[:error] }).not_to include(:prepaid_amount_negative, :prepaid_amount_exceeds_total)
    end

    it "reports a negative prepaid_amount" do
      inv = Einvoicing::Invoice.new(
        invoice_number: "INV-001",
        issue_date:     Date.today,
        seller:         Fixtures.seller,
        buyer:          Fixtures.buyer,
        lines:          [ Fixtures.line ],
        prepaid_amount: BigDecimal("-1")
      )
      errors = described_class.validate(inv)
      expect(errors).to include(a_hash_including(field: :prepaid_amount, error: :prepaid_amount_negative))
    end

    it "reports a prepaid_amount exceeding gross_total" do
      inv = Einvoicing::Invoice.new(
        invoice_number: "INV-001",
        issue_date:     Date.today,
        seller:         Fixtures.seller,
        buyer:          Fixtures.buyer,
        lines:          [ Fixtures.line ],
        prepaid_amount: BigDecimal("99999")
      )
      errors = described_class.validate(inv)
      expect(errors).to include(a_hash_including(field: :prepaid_amount, error: :prepaid_amount_exceeds_total))
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

  describe "document-level allowances and charges" do
    def invoice_with(allowances: [], charges: [])
      Einvoicing::Invoice.new(
        invoice_number: "INV-001",
        issue_date:     Date.today,
        seller:         Fixtures.seller,
        buyer:          Fixtures.buyer,
        lines:          [ Fixtures.line ],
        allowances:     allowances,
        charges:        charges
      )
    end

    it "accepts an allowance carrying a reason and a standard rate" do
      item = Einvoicing::AllowanceCharge.new(amount: "100.00", vat_rate: 0.20, reason: "Remise")
      expect(described_class.validate(invoice_with(allowances: [ item ]))).to be_empty
    end

    it "accepts a reason code instead of a reason (BR-33)" do
      item = Einvoicing::AllowanceCharge.new(amount: "100.00", vat_rate: 0.20, reason_code: "95")
      expect(described_class.validate(invoice_with(allowances: [ item ]))).to be_empty
    end

    it "reports an allowance without reason nor reason code" do
      item = Einvoicing::AllowanceCharge.new(amount: "100.00", vat_rate: 0.20)
      errors = described_class.validate(invoice_with(allowances: [ item ]))

      expect(errors).to include(a_hash_including(field: :allowance_1_reason, error: :reason_missing))
    end

    it "reports a negative allowance amount" do
      item = Einvoicing::AllowanceCharge.new(amount: "-10.00", vat_rate: 0.20, reason: "Remise")
      errors = described_class.validate(invoice_with(allowances: [ item ]))

      expect(errors).to include(a_hash_including(field: :allowance_1_amount, error: :amount_invalid))
    end

    it "reports a non-French VAT rate on a charge" do
      item = Einvoicing::AllowanceCharge.new(amount: "10.00", vat_rate: 0.17, reason: "Frais")
      errors = described_class.validate(invoice_with(charges: [ item ]))

      expect(errors).to include(a_hash_including(field: :charge_1_vat_rate, error: :vat_rate_invalid))
    end
  end
end
