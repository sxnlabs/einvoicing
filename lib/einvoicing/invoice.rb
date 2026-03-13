# frozen_string_literal: true

require "date"

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
    :seller,
    :buyer,
    :lines,
    :tax_breakdown,
    :payment_reference,
    :note
  ) do
    def initialize(invoice_number:, issue_date:, seller:, buyer:, lines:,
                   due_date: nil, currency: "EUR", tax_breakdown: nil,
                   payment_reference: nil, note: nil)
      computed_breakdown = tax_breakdown || compute_tax_breakdown(lines)
      super(
        invoice_number: invoice_number,
        issue_date: issue_date,
        due_date: due_date,
        currency: currency,
        seller: seller,
        buyer: buyer,
        lines: lines,
        tax_breakdown: computed_breakdown,
        payment_reference: payment_reference,
        note: note
      )
    end

    # Sum of all line net amounts (excl. VAT).
    def net_total
      lines.sum(&:net_amount).round(2)
    end

    # Total VAT across all lines.
    def tax_total
      tax_breakdown.sum(&:tax_amount).round(2)
    end

    # Grand total including VAT.
    def gross_total
      (net_total + tax_total).round(2)
    end

    # Amount due (same as gross_total; override for prepayments).
    def due_amount
      gross_total
    end

    private

    def compute_tax_breakdown(lines)
      grouped = lines.group_by(&:vat_rate)
      grouped.map do |rate, rate_lines|
        taxable = rate_lines.sum(&:net_amount).round(2)
        tax_amt = rate_lines.sum(&:vat_amount).round(2)
        Tax.new(rate: rate, taxable_amount: taxable, tax_amount: tax_amt)
      end
    end
  end
end
