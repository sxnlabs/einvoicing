# frozen_string_literal: true

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
  LineItem = Data.define(:description, :quantity, :unit_price, :vat_rate, :unit) do
    def initialize(description:, quantity:, unit_price:, vat_rate: 0.20, unit: "C62")
      super
    end

    # Net line total (excluding VAT).
    def net_amount
      (quantity * unit_price).round(2)
    end

    # VAT amount for this line.
    def vat_amount
      (net_amount * vat_rate).round(2)
    end

    # Gross line total (including VAT).
    def gross_amount
      (net_amount + vat_amount).round(2)
    end

    def vat_rate_percent
      (vat_rate * 100).round(2)
    end

    # CII/UBL tax category code.
    def tax_category_code
      vat_rate == 0 ? "Z" : "S"
    end
  end
end
