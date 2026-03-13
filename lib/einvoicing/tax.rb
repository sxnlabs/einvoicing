# frozen_string_literal: true

require "bigdecimal"
require "bigdecimal/util"

module Einvoicing
  # VAT breakdown entry for a single tax rate.
  Tax = Data.define(:rate, :taxable_amount, :tax_amount, :category) do
    # @param rate [Numeric] e.g. 0.20 for 20% VAT; 0 for zero-rated or reverse charge
    # @param taxable_amount [Numeric] net amount subject to this rate
    # @param tax_amount [Numeric] VAT amount for this rate
    # @param category [Symbol, nil] nil for standard/zero, :reverse_charge for AE
    def initialize(rate:, taxable_amount:, tax_amount:, category: nil)
      raise ArgumentError, "rate must be >= 0, got #{rate}" if rate.to_f.negative?

      super
    end

    # Shared lookup used by both Tax and LineItem.
    def self.category_code_for(rate:, category: nil)
      if rate.to_f == 0.0
        category == :reverse_charge ? "AE" : "Z"
      else
        "S"
      end
    end

    def category_code
      Tax.category_code_for(rate: rate, category: category)
    end

    def rate_percent
      return BigDecimal("0") if category == :reverse_charge

      (BigDecimal(rate.to_s) * 100).round(2)
    end
  end
end
