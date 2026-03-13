# frozen_string_literal: true

require "bigdecimal"
require "bigdecimal/util"

module Einvoicing
  # A single line on an invoice.
  #
  # @example
  #   Einvoicing::LineItem.new(
  #     description: "Software consulting",
  #     quantity: 5,
  #     unit_price: 150.00,
  #     vat_rate: 0.20
  #   )
  LineItem = Data.define(:description, :quantity, :unit_price, :vat_rate, :unit, :category) do
    def initialize(description:, quantity:, unit_price:, vat_rate: 0.20, unit: "C62", category: nil)
      super(
        description: description,
        quantity:    BigDecimal(quantity.to_s),
        unit_price:  BigDecimal(unit_price.to_s),
        vat_rate:    vat_rate,
        unit:        unit,
        category:    category
      )
    end

    # Net line total (excluding VAT).
    def net_amount
      (quantity * unit_price).round(2, :half_up)
    end

    # VAT amount for this line.
    def vat_amount
      (net_amount * BigDecimal(vat_rate.to_s)).round(2, :half_up)
    end

    # Gross line total (including VAT).
    def gross_amount
      (net_amount + vat_amount).round(2, :half_up)
    end

    def vat_rate_percent
      return BigDecimal("0") if category == :reverse_charge

      (BigDecimal(vat_rate.to_s) * 100).round(2)
    end

    # CII/UBL tax category code — delegates to shared Tax logic.
    def tax_category_code
      Tax.category_code_for(rate: vat_rate, category: category)
    end
  end
end
