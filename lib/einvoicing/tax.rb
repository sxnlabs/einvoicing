# frozen_string_literal: true

module Einvoicing
  # VAT breakdown entry for a single tax rate.
  Tax = Data.define(:rate, :taxable_amount, :tax_amount) do
    # @param rate [Float] e.g. 0.20 for 20% VAT
    # @param taxable_amount [Numeric] net amount subject to this rate
    # @param tax_amount [Numeric] VAT amount for this rate
    def initialize(rate:, taxable_amount:, tax_amount:)
      super
    end

    def category_code
      case rate
      when 0     then "Z"
      when -1    then "AE"  # reverse charge
      else            "S"
      end
    end

    def rate_percent
      (rate * 100).round(2)
    end
  end
end
