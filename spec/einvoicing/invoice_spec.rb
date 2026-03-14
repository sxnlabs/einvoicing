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
