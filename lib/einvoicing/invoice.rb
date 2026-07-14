# frozen_string_literal: true

require "bigdecimal"
require "bigdecimal/util"

module Einvoicing
  # Core invoice model. All monetary values are in the invoice currency.
  #
  # @example
  #   seller = Einvoicing::Party.new(name: "Acme SAS", siren: "123456789", vat_number: "FR12123456789")
  #   buyer  = Einvoicing::Party.new(name: "Client SA", siren: "987654321")
  #   line   = Einvoicing::LineItem.new(description: "Consulting", quantity: 1, unit_price: 1000.00)
  #
  #   invoice = Einvoicing::Invoice.new(
  #     invoice_number: "INV-2024-001",
  #     issue_date: Date.today,
  #     seller: seller,
  #     buyer: buyer,
  #     lines: [line]
  #   )
  Invoice = Data.define(
    :invoice_number,
    :issue_date,
    :due_date,
    :currency,
    :tax_currency,
    :seller,
    :buyer,
    :lines,
    :tax_breakdown,
    :payment_reference,
    :note,
    :payment_means_code,
    :iban,
    :bic,
    :document_type,
    :original_invoice_number,
    :original_invoice_date,
    :prepaid_amount
  ) do
    def initialize(invoice_number:, issue_date:, seller:, buyer:, lines:,
                   due_date: nil, currency: "EUR", tax_currency: nil, tax_breakdown: nil,
                   payment_reference: nil, note: nil,
                   payment_means_code: nil, iban: nil, bic: nil,
                   document_type: :invoice, original_invoice_number: nil, original_invoice_date: nil,
                   prepaid_amount: BigDecimal(0))
      computed_breakdown = tax_breakdown || compute_tax_breakdown(lines)
      super(
        invoice_number: invoice_number,
        issue_date: issue_date,
        due_date: due_date,
        currency: currency,
        tax_currency: tax_currency,
        seller: seller,
        buyer: buyer,
        lines: lines,
        tax_breakdown: computed_breakdown,
        payment_reference: payment_reference,
        note: note,
        payment_means_code: payment_means_code,
        iban: iban,
        bic: bic,
        document_type: document_type,
        original_invoice_number: original_invoice_number,
        original_invoice_date: original_invoice_date,
        prepaid_amount: prepaid_amount.nil? ? BigDecimal(0) : BigDecimal(prepaid_amount.to_s)
      )
    end

    # Sum of all line net amounts (excl. VAT).
    def net_total
      lines.sum(BigDecimal("0"), &:net_amount).round(2, :half_up)
    end

    # Total VAT across all lines.
    def tax_total
      tax_breakdown.sum(BigDecimal("0"), &:tax_amount).round(2, :half_up)
    end

    # Grand total including VAT — computed from per-line gross amounts to avoid
    # double-rounding through already-rounded net_total/tax_total (EN 16931 BR-CO-13).
    def gross_total
      lines.sum(BigDecimal("0"), &:gross_amount).round(2, :half_up)
    end

    # Amount due after deducting any retained/prepaid amount (BT-113).
    # VAT remains due on the full gross_total — only the payable balance is reduced
    # (EN 16931 BR-CO-16: DuePayableAmount = GrandTotal − TotalPrepaidAmount).
    def due_amount
      gross_total - prepaid_amount
    end

    private

    def compute_tax_breakdown(lines)
      grouped = lines.group_by { |l| [ l.vat_rate, l.category ] }
      grouped.map do |(rate, category), rate_lines|
        taxable = rate_lines.sum(BigDecimal("0"), &:net_amount).round(2, :half_up)
        tax_amt = rate_lines.sum(BigDecimal("0"), &:vat_amount).round(2, :half_up)
        Tax.new(rate: rate, taxable_amount: taxable, tax_amount: tax_amt, category: category)
      end
    end
  end
end
