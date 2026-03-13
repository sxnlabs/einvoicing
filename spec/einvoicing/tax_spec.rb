# frozen_string_literal: true

require "spec_helper"

RSpec.describe Einvoicing::Tax do
  describe ".new" do
    it "accepts rate 0.20" do
      tax = described_class.new(rate: 0.20, taxable_amount: 100, tax_amount: 20)
      expect(tax.rate).to eq(0.20)
    end

    it "accepts rate 0.10" do
      tax = described_class.new(rate: 0.10, taxable_amount: 100, tax_amount: 10)
      expect(tax.rate).to eq(0.10)
    end

    it "accepts rate 0.055" do
      tax = described_class.new(rate: 0.055, taxable_amount: 100, tax_amount: 5.5)
      expect(tax.rate).to eq(0.055)
    end

    it "accepts rate 0.021" do
      tax = described_class.new(rate: 0.021, taxable_amount: 100, tax_amount: 2.1)
      expect(tax.rate).to eq(0.021)
    end

    it "accepts rate 0.0 (zero-rated)" do
      tax = described_class.new(rate: 0.0, taxable_amount: 100, tax_amount: 0)
      expect(tax.rate).to eq(0.0)
    end

    it "raises ArgumentError for negative rate" do
      expect {
        described_class.new(rate: -0.1, taxable_amount: 100, tax_amount: -10)
      }.to raise_error(ArgumentError, /rate must be >= 0/)
    end
  end

  describe "#category_code" do
    it "returns 'S' for standard rate 0.20" do
      tax = described_class.new(rate: 0.20, taxable_amount: 100, tax_amount: 20)
      expect(tax.category_code).to eq("S")
    end

    it "returns 'S' for standard rate 0.10" do
      tax = described_class.new(rate: 0.10, taxable_amount: 100, tax_amount: 10)
      expect(tax.category_code).to eq("S")
    end

    it "returns 'Z' for zero rate" do
      tax = described_class.new(rate: 0.0, taxable_amount: 100, tax_amount: 0)
      expect(tax.category_code).to eq("Z")
    end

    it "returns 'AE' for reverse_charge category" do
      tax = described_class.new(rate: 0.0, taxable_amount: 100, tax_amount: 0, category: :reverse_charge)
      expect(tax.category_code).to eq("AE")
    end
  end

  describe "reverse_charge" do
    let(:tax) { described_class.new(rate: 0, taxable_amount: 500, tax_amount: 0, category: :reverse_charge) }

    it "has rate 0" do
      expect(tax.rate.to_f).to eq(0.0)
    end

    it "has category_code 'AE'" do
      expect(tax.category_code).to eq("AE")
    end

    it "has rate_percent 0" do
      expect(tax.rate_percent).to eq(BigDecimal("0"))
    end
  end
end
