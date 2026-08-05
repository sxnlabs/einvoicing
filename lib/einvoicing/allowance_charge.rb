# frozen_string_literal: true

require "bigdecimal"
require "bigdecimal/util"

module Einvoicing
  # A document-level allowance (BG-20) or charge (BG-21).
  #
  # The same shape covers both: whether it is deducted or added is decided by
  # the array it sits in on the invoice (`allowances:` or `charges:`), so the
  # amount itself is always expressed as a positive value.
  #
  # @example A 10% commercial discount on a 20% VAT base
  #   Einvoicing::AllowanceCharge.new(
  #     amount:      BigDecimal("100.00"),
  #     vat_rate:    0.20,
  #     reason:      "Remise commerciale",
  #     reason_code: "95",
  #     base_amount: BigDecimal("1000.00"),
  #     percentage:  10
  #   )
  AllowanceCharge = Data.define(:amount, :vat_rate, :category, :reason,
                                :reason_code, :base_amount, :percentage,
                                :exemption_reason, :exemption_reason_code) do
    # @param amount [Numeric] BT-92 / BT-99 — always positive
    # @param vat_rate [Numeric] BT-96 / BT-103 — the rate the amount applies to
    # @param category [Symbol, nil] a key of Einvoicing::Tax::CATEGORY_CODES;
    #   nil infers standard or zero-rated from the rate
    # @param reason [String, nil] BT-97 / BT-104
    # @param reason_code [String, nil] BT-98 / BT-105 (UNCL5189 / UNCL7161)
    # @param base_amount [Numeric, nil] BT-93 / BT-100
    # @param percentage [Numeric, nil] BT-94 / BT-101
    # @param exemption_reason [String, nil] BT-120, carried into the VAT breakdown
    # @param exemption_reason_code [String, nil] BT-121, carried into the VAT breakdown
    def initialize(amount:, vat_rate: 0.20, category: nil, reason: nil,
                   reason_code: nil, base_amount: nil, percentage: nil,
                   exemption_reason: nil, exemption_reason_code: nil)
      super(
        amount:      BigDecimal(amount.to_s),
        vat_rate:    vat_rate,
        category:    category,
        reason:      reason,
        reason_code: reason_code,
        base_amount: base_amount.nil? ? nil : BigDecimal(base_amount.to_s),
        percentage:  percentage,
        exemption_reason:      exemption_reason,
        exemption_reason_code: exemption_reason_code
      )
    end

    # VAT carried by this allowance/charge at its own rate.
    def vat_amount
      (amount * Tax.effective_rate(rate: vat_rate, category: category)).round(2, :half_up)
    end

    def vat_rate_percent
      (Tax.effective_rate(rate: vat_rate, category: category) * 100).round(2)
    end

    # CII/UBL tax category code — delegates to shared Tax logic.
    def tax_category_code
      Tax.category_code_for(rate: vat_rate, category: category)
    end
  end
end
