# frozen_string_literal: true

require "spec_helper"

RSpec.describe Einvoicing::Invoice do
  describe "VAT breakdown arithmetic (BR-S-09, BR-CO-14)" do
  # Each line rounds to a half-cent, so summing the rounded per-line VAT drifts
  # away from base × rate. EN 16931 pins BT-117 to the base, not to the lines.
  let(:drifting_lines) do
    Array.new(40) do |i|
      Einvoicing::LineItem.new(description: "Item #{i + 1}", quantity: 3,
                               unit_price: BigDecimal("10.075"), vat_rate: 0.20)
    end
  end

  let(:invoice) do
    described_class.new(
      invoice_number: "INV-2026-500",
      issue_date:     Date.new(2026, 1, 15),
      seller:         Fixtures.seller,
      buyer:          Fixtures.buyer,
      lines:          drifting_lines
    )
  end

  it "derives each category's VAT from its rounded taxable base" do
    tax = invoice.tax_breakdown.first
    expect(tax.tax_amount).to eq((tax.taxable_amount * BigDecimal("0.20")).round(2, :half_up))
  end

  it "no longer inherits the drift from summing rounded line VAT" do
    summed = drifting_lines.sum(BigDecimal("0"), &:vat_amount)
    expect(invoice.tax_breakdown.first.tax_amount).not_to eq(summed)
  end

  it "keeps BT-110 equal to the sum of the breakdown (BR-CO-14)" do
    expect(invoice.tax_total).to eq(invoice.tax_breakdown.sum(BigDecimal("0"), &:tax_amount))
  end

  it "keeps BR-CO-15: gross = net + VAT" do
    expect(invoice.gross_total).to eq(invoice.net_total + invoice.tax_total)
  end

  it "still nets document allowances and charges into their own category base" do
    inv = described_class.new(
      invoice_number: "INV-2026-501",
      issue_date:     Date.new(2026, 1, 15),
      seller:         Fixtures.seller,
      buyer:          Fixtures.buyer,
      lines:          [ Fixtures.line ],                        # 5 × 200.00 = 1000.00
      allowances:     [ Einvoicing::AllowanceCharge.new(amount: "100.00", vat_rate: 0.20,
                                                        reason: "Remise") ],
      charges:        [ Einvoicing::AllowanceCharge.new(amount: "50.00", vat_rate: 0.20,
                                                        reason: "Port") ]
    )
    tax = inv.tax_breakdown.first
    expect(tax.taxable_amount).to eq(BigDecimal("950.00"))
    expect(tax.tax_amount).to eq(BigDecimal("190.00"))
  end
  end

  describe "VAT accounting currency (BT-6 / BT-111, BR-53)" do
    def usd_invoice(**overrides)
      Einvoicing::Invoice.new(
        invoice_number: "INV-2026-USD",
        issue_date:     Date.new(2026, 1, 15),
        seller:         Fixtures.seller,
        buyer:          Fixtures.buyer,
        lines:          [ Fixtures.line ],
        currency:       "USD",
        **overrides
      )
    end

    it "reports no accounting currency when BT-6 matches BT-5" do
      expect(usd_invoice(tax_currency: "USD").tax_accounting_currency?).to be(false)
    end

    it "converts the VAT total at the given exchange rate" do
      invoice = usd_invoice(tax_currency: "EUR", tax_exchange_rate: "0.92")
      expect(invoice.tax_total).to eq(BigDecimal("200.00"))
      expect(invoice.tax_total_in_tax_currency).to eq(BigDecimal("184.00"))
    end

    it "emits TaxCurrencyCode before InvoiceCurrencyCode and a second TaxTotalAmount in CII" do
      xml = Einvoicing::Formats::CII.generate(usd_invoice(tax_currency: "EUR",
                                                          tax_exchange_rate: "0.92"))
      expect(xml).to match(
        %r{<ram:TaxCurrencyCode>EUR</ram:TaxCurrencyCode>\s*
           <ram:InvoiceCurrencyCode>USD</ram:InvoiceCurrencyCode>}x
      )
      expect(xml).to include('<ram:TaxTotalAmount currencyID="EUR">184.00</ram:TaxTotalAmount>')
    end

    it "emits a second cac:TaxTotal in UBL" do
      xml = Einvoicing::Formats::UBL.generate(usd_invoice(tax_currency: "EUR",
                                                          tax_exchange_rate: "0.92"))
      expect(xml).to include('<cbc:TaxAmount currencyID="EUR">184.00</cbc:TaxAmount>')
      expect(xml).to include("<cbc:TaxCurrencyCode>EUR</cbc:TaxCurrencyCode>")
    end

    it "flags a declared accounting currency with no way to convert (BR-53)" do
      errors = Einvoicing::Validators::FR.validate(usd_invoice(tax_currency: "EUR"))
      expect(errors).to include(a_hash_including(error: :tax_exchange_rate_missing))
    end

    it "emits nothing extra when no accounting currency is declared" do
      xml = Einvoicing::Formats::CII.generate(usd_invoice)
      expect(xml).not_to include("TaxCurrencyCode")
      expect(xml.scan("ram:TaxTotalAmount").size).to eq(2) # one open + one close tag
    end
  end
end
