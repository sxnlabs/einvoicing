# frozen_string_literal: true

require "spec_helper"

RSpec.describe Einvoicing::AllowanceCharge do
  subject(:allowance) do
    described_class.new(amount: "100.00", vat_rate: 0.20, reason: "Remise commerciale",
                        reason_code: "95", base_amount: "1000.00", percentage: 10)
  end

  it "coerces monetary values to BigDecimal" do
    expect(allowance.amount).to eq(BigDecimal("100.00"))
    expect(allowance.base_amount).to eq(BigDecimal("1000.00"))
  end

  it "computes the VAT it carries at its own rate" do
    expect(allowance.vat_amount).to eq(BigDecimal("20.00"))
  end

  it "exposes the rate as a percentage" do
    expect(allowance.vat_rate_percent).to eq(BigDecimal("20"))
  end

  it "maps to the standard tax category code" do
    expect(allowance.tax_category_code).to eq("S")
  end

  it "leaves base_amount and percentage nil when not provided" do
    item = described_class.new(amount: "50.00")
    expect(item.base_amount).to be_nil
    expect(item.percentage).to be_nil
  end

  it "reports a zero rate as category Z" do
    item = described_class.new(amount: "50.00", vat_rate: 0)
    expect(item.tax_category_code).to eq("Z")
    expect(item.vat_amount).to eq(BigDecimal("0"))
  end

  it "reports reverse charge as category AE with a zero displayed rate" do
    item = described_class.new(amount: "50.00", vat_rate: 0, category: :reverse_charge)
    expect(item.tax_category_code).to eq("AE")
    expect(item.vat_rate_percent).to eq(BigDecimal("0"))
  end
end
