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
    :allowances,
    :charges,
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
                   allowances: [], charges: [],
                   due_date: nil, currency: "EUR", tax_currency: nil, tax_breakdown: nil,
                   payment_reference: nil, note: nil,
                   payment_means_code: nil, iban: nil, bic: nil,
                   document_type: :invoice, original_invoice_number: nil, original_invoice_date: nil,
                   prepaid_amount: BigDecimal(0))
      allowances = allowances || []
      charges = charges || []
      computed_breakdown = tax_breakdown || compute_tax_breakdown(lines, allowances, charges)
      super(
        invoice_number: invoice_number,
        issue_date: issue_date,
        due_date: due_date,
        currency: currency,
        tax_currency: tax_currency,
        seller: seller,
        buyer: buyer,
        lines: lines,
        allowances: allowances,
        charges: charges,
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

    # Data#with feeds every current member back through the constructor, which
    # would carry the already-computed tax_breakdown over to the copy and leave
    # it stale. Drop it so the copy recomputes — unless the caller supplies one.
    RECOMPUTES_TAX_BREAKDOWN = %i[lines allowances charges].freeze

    def with(**kwargs)
      return super if kwargs.key?(:tax_breakdown)
      return super if (kwargs.keys & RECOMPUTES_TAX_BREAKDOWN).empty?

      super(**kwargs, tax_breakdown: nil)
    end

    # Sum of all line net amounts, before document-level adjustments (BT-106).
    def line_total
      lines.sum(BigDecimal("0"), &:net_amount).round(2, :half_up)
    end

    # Sum of document-level allowances (BT-107).
    def allowance_total
      allowances.sum(BigDecimal("0"), &:amount).round(2, :half_up)
    end

    # Sum of document-level charges (BT-108).
    def charge_total
      charges.sum(BigDecimal("0"), &:amount).round(2, :half_up)
    end

    # Total amount without VAT (BT-109) — BR-CO-13:
    # line_total − allowance_total + charge_total.
    def net_total
      (line_total - allowance_total + charge_total).round(2, :half_up)
    end

    # Total VAT across every category (BT-110).
    def tax_total
      tax_breakdown.sum(BigDecimal("0"), &:tax_amount).round(2, :half_up)
    end

    # Grand total including VAT (BT-112) — BR-CO-15: net_total + tax_total.
    # Both operands are already rounded to 2 decimals from per-line amounts, so
    # this introduces no double-rounding.
    def gross_total
      (net_total + tax_total).round(2, :half_up)
    end

    # Amount due after deducting any retained/prepaid amount (BT-113).
    # VAT remains due on the full gross_total — only the payable balance is reduced
    # (EN 16931 BR-CO-16: DuePayableAmount = GrandTotal − TotalPrepaidAmount).
    def due_amount
      gross_total - prepaid_amount
    end

    private

    # Per-category taxable base (BT-116) and VAT (BT-117), adjusted by the
    # document-level allowances and charges that carry the same rate/category
    # (EN 16931 BR-CO-10 through BR-CO-12).
    def compute_tax_breakdown(lines, allowances, charges)
      key = ->(item) { [ item.vat_rate, item.category ] }
      grouped_lines      = lines.group_by(&key)
      grouped_allowances = allowances.group_by(&key)
      grouped_charges    = charges.group_by(&key)

      (grouped_lines.keys | grouped_allowances.keys | grouped_charges.keys).map do |(rate, category)|
        k = [ rate, category ]
        rate_lines      = grouped_lines.fetch(k, [])
        rate_allowances = grouped_allowances.fetch(k, [])
        rate_charges    = grouped_charges.fetch(k, [])

        taxable = sum_of(rate_lines, :net_amount) -
                  sum_of(rate_allowances, :amount) +
                  sum_of(rate_charges, :amount)
        tax_amt = sum_of(rate_lines, :vat_amount) -
                  sum_of(rate_allowances, :vat_amount) +
                  sum_of(rate_charges, :vat_amount)

        Tax.new(rate: rate, taxable_amount: taxable.round(2, :half_up),
                tax_amount: tax_amt.round(2, :half_up), category: category)
      end
    end

    def sum_of(items, method)
      items.sum(BigDecimal("0"), &method)
    end
  end
end
