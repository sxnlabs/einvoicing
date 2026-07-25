# frozen_string_literal: true

require "spec_helper"

RSpec.describe Einvoicing::Invoice do
  let(:invoice) { Fixtures.invoice }

  describe "totals" do
    it "computes net_total" do
      # 5 lines × 200.00 = 1000.00
      expect(invoice.net_total).to eq(1000.00)
    end

    it "computes tax_total at 20%" do
      expect(invoice.tax_total).to eq(200.00)
    end

    it "computes gross_total" do
      expect(invoice.gross_total).to eq(1200.00)
    end
  end

  describe "auto tax breakdown" do
    it "groups lines by VAT rate" do
      lines = [
        Fixtures.line(vat_rate: 0.20),
        Fixtures.line(vat_rate: 0.10)
      ]
      inv = Fixtures.invoice(lines: lines)
      expect(inv.tax_breakdown.size).to eq(2)
    end

    it "computes correct amounts per rate" do
      inv = Fixtures.invoice(lines: [ Fixtures.line(vat_rate: 0.20) ])
      tax = inv.tax_breakdown.first
      expect(tax.rate).to eq(0.20)
      expect(tax.taxable_amount).to eq(1000.00)
      expect(tax.tax_amount).to eq(200.00)
    end
  end

  describe "defaults" do
    it "defaults currency to EUR" do
      expect(invoice.currency).to eq("EUR")
    end
  end

  describe "prepaid_amount (BT-113, retenue de garantie)" do
    it "defaults due_amount to gross_total when no prepaid amount is set" do
      expect(invoice.prepaid_amount).to eq(BigDecimal("0"))
      expect(invoice.due_amount).to eq(invoice.gross_total)
    end

    it "reduces due_amount without changing net_total, tax_total or gross_total" do
      inv = described_class.new(
        invoice_number: "INV-2024-001",
        issue_date:     Date.new(2024, 1, 15),
        seller:         Fixtures.seller,
        buyer:          Fixtures.buyer,
        lines:          [ Fixtures.line ],
        prepaid_amount: BigDecimal("100")
      )

      expect(inv.net_total).to eq(1000.00)
      expect(inv.tax_total).to eq(200.00)
      expect(inv.gross_total).to eq(1200.00)
      expect(inv.due_amount).to eq(1100.00)
    end

    it "coerces a numeric prepaid_amount to BigDecimal" do
      inv = described_class.new(
        invoice_number: "INV-2024-001",
        issue_date:     Date.new(2024, 1, 15),
        seller:         Fixtures.seller,
        buyer:          Fixtures.buyer,
        lines:          [ Fixtures.line ],
        prepaid_amount: 100
      )

      expect(inv.prepaid_amount).to be_a(BigDecimal)
      expect(inv.due_amount).to eq(1100.00)
    end

    it "tolerates an explicit nil prepaid_amount" do
      inv = described_class.new(
        invoice_number: "INV-2024-001",
        issue_date:     Date.new(2024, 1, 15),
        seller:         Fixtures.seller,
        buyer:          Fixtures.buyer,
        lines:          [ Fixtures.line ],
        prepaid_amount: nil
      )

      expect(inv.prepaid_amount).to eq(BigDecimal("0"))
      expect(inv.due_amount).to eq(inv.gross_total)
    end
  end

  describe "document-level allowances and charges (BG-20 / BG-21)" do
    def invoice_with(allowances: [], charges: [])
      described_class.new(
        invoice_number: "INV-2024-001",
        issue_date:     Date.new(2024, 1, 15),
        seller:         Fixtures.seller,
        buyer:          Fixtures.buyer,
        lines:          [ Fixtures.line ],
        allowances:     allowances,
        charges:        charges
      )
    end

    let(:allowance) do
      Einvoicing::AllowanceCharge.new(amount: "100.00", vat_rate: 0.20, reason: "Remise")
    end
    let(:charge) do
      Einvoicing::AllowanceCharge.new(amount: "50.00", vat_rate: 0.20, reason: "Frais de port")
    end

    it "defaults to empty collections" do
      inv = Fixtures.invoice
      expect(inv.allowances).to eq([])
      expect(inv.charges).to eq([])
      expect(inv.allowance_total).to eq(0)
      expect(inv.charge_total).to eq(0)
    end

    it "keeps line_total untouched and deducts allowances from net_total (BR-CO-13)" do
      inv = invoice_with(allowances: [ allowance ])

      expect(inv.line_total).to eq(1000.00)
      expect(inv.allowance_total).to eq(100.00)
      expect(inv.net_total).to eq(900.00)
    end

    it "adds charges to net_total" do
      inv = invoice_with(charges: [ charge ])

      expect(inv.charge_total).to eq(50.00)
      expect(inv.net_total).to eq(1050.00)
    end

    it "adjusts the VAT breakdown of the matching rate (BR-CO-10 to BR-CO-12)" do
      inv = invoice_with(allowances: [ allowance ], charges: [ charge ])
      tax = inv.tax_breakdown.first

      expect(inv.tax_breakdown.size).to eq(1)
      expect(tax.taxable_amount).to eq(950.00)
      expect(tax.tax_amount).to eq(190.00)
    end

    it "keeps gross_total equal to net_total + tax_total (BR-CO-15)" do
      inv = invoice_with(allowances: [ allowance ], charges: [ charge ])

      expect(inv.net_total).to eq(950.00)
      expect(inv.tax_total).to eq(190.00)
      expect(inv.gross_total).to eq(1140.00)
      expect(inv.due_amount).to eq(1140.00)
    end

    it "opens a VAT category that no line uses" do
      zero_rated = Einvoicing::AllowanceCharge.new(amount: "30.00", vat_rate: 0.0, reason: "Éco-contribution")
      inv = invoice_with(charges: [ zero_rated ])

      expect(inv.tax_breakdown.map(&:rate)).to contain_exactly(0.20, 0.0)
      expect(inv.tax_breakdown.find { |t| t.rate.zero? }.taxable_amount).to eq(30.00)
      expect(inv.tax_total).to eq(200.00)
      expect(inv.gross_total).to eq(1230.00)
    end

    it "recomputes the tax breakdown when #with changes the amounts" do
      inv = Fixtures.invoice.with(allowances: [ allowance ])

      expect(inv.tax_breakdown.first.taxable_amount).to eq(900.00)
      expect(inv.tax_total).to eq(180.00)
    end

    it "keeps an explicitly supplied tax breakdown through #with" do
      breakdown = [ Einvoicing::Tax.new(rate: 0.20, taxable_amount: 1, tax_amount: 2) ]
      inv = Fixtures.invoice.with(allowances: [ allowance ], tax_breakdown: breakdown)

      expect(inv.tax_breakdown).to eq(breakdown)
    end

    it "tolerates explicit nil collections" do
      inv = described_class.new(
        invoice_number: "INV-2024-001",
        issue_date:     Date.new(2024, 1, 15),
        seller:         Fixtures.seller,
        buyer:          Fixtures.buyer,
        lines:          [ Fixtures.line ],
        allowances:     nil,
        charges:        nil
      )

      expect(inv.net_total).to eq(1000.00)
    end
  end

  describe Einvoicing::Party do
    it "derives siren from siret" do
      party = described_class.new(name: "Test", siret: "35600000000048")
      expect(party.siren_number).to eq("356000000")
    end

    it "prefers siren over siret-derived value" do
      party = described_class.new(name: "Test", siren: "123456789", siret: "12345678900001")
      expect(party.siren_number).to eq("123456789")
    end
  end

  describe Einvoicing::LineItem do
    let(:line) { Fixtures.line }

    it "computes net_amount" do
      expect(line.net_amount).to eq(1000.00)
    end

    it "computes vat_amount" do
      expect(line.vat_amount).to eq(200.00)
    end

    it "computes gross_amount" do
      expect(line.gross_amount).to eq(1200.00)
    end

    it "returns C62 as default unit" do
      expect(line.unit).to eq("C62")
    end

    it "returns S category code for standard rate" do
      expect(line.tax_category_code).to eq("S")
    end

    it "returns Z category code for zero rate" do
      zero_line = described_class.new(description: "Exempt", quantity: 1, unit_price: 100.0, vat_rate: 0.0)
      expect(zero_line.tax_category_code).to eq("Z")
    end
  end
end
