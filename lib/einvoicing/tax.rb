# frozen_string_literal: true

require "bigdecimal"
require "bigdecimal/util"

module Einvoicing
  # VAT breakdown entry (BG-23) for a single rate/category pair.
  class Tax < Data.define(:rate, :taxable_amount, :tax_amount, :category,
                          :exemption_reason, :exemption_reason_code)
    # EN 16931 BT-118 — the UNCL5305 subset the standard allows.
    CATEGORY_CODES = {
      standard:        "S",   # Standard rate
      zero_rated:      "Z",   # Zero rated goods
      exempt:          "E",   # Exempt from VAT
      reverse_charge:  "AE",  # VAT reverse charge
      intra_community: "K",   # Intra-Community supply
      export:          "G",   # Export outside the EU
      not_subject:     "O"    # Services outside scope of tax
    }.freeze

    # BR-E-10, BR-AE-10, BR-IC-10, BR-G-10, BR-O-10: these categories must carry
    # a VAT exemption reason (BT-120) or reason code (BT-121). BR-Z-10 and the
    # standard category must NOT carry one.
    EXEMPTION_REQUIRED_CODES = %w[E AE K G O].freeze

    # Categories that net out to 0 % VAT whatever rate the caller passed in.
    ZERO_VAT_CODES = %w[Z E AE K G O].freeze

    # Defaults from the EN 16931 VATEX code list. "E" is deliberately absent:
    # the reason depends on which exemption is invoked, so the caller supplies
    # it (e.g. VATEX_FR_FRANCHISE for the French art. 293 B franchise).
    DEFAULT_EXEMPTIONS = {
      "AE" => [ "VATEX-EU-AE", "Reverse charge" ],
      "K"  => [ "VATEX-EU-IC", "Intra-Community supply" ],
      "G"  => [ "VATEX-EU-G",  "Export outside the EU" ],
      "O"  => [ "VATEX-EU-O",  "Not subject to VAT" ]
    }.freeze

    # France, art. 293 B du CGI — franchise en base de TVA.
    VATEX_FR_FRANCHISE = "VATEX-FR-FRANCHISE"

    # Shared lookup used by Tax, LineItem and AllowanceCharge.
    def self.category_code_for(rate:, category: nil)
      return rate.to_f.zero? ? "Z" : "S" if category.nil?

      CATEGORY_CODES.fetch(category) do
        raise ArgumentError, Einvoicing::I18n.t("tax.unknown_category", category: category.inspect)
      end
    end

    # The rate actually billed once the category is taken into account: an
    # exempt / reverse-charge / out-of-scope category charges 0 % whatever rate
    # was passed in.
    def self.effective_rate(rate:, category: nil)
      return BigDecimal("0") if ZERO_VAT_CODES.include?(category_code_for(rate: rate, category: category))

      BigDecimal(rate.to_s)
    end

    # @param rate [Numeric] e.g. 0.20 for 20% VAT; 0 for zero-rated or exempt
    # @param taxable_amount [Numeric] net amount subject to this rate (BT-116)
    # @param tax_amount [Numeric] VAT amount for this rate (BT-117)
    # @param category [Symbol, nil] a key of CATEGORY_CODES; nil infers standard
    #   or zero-rated from the rate
    # @param exemption_reason [String, nil] BT-120
    # @param exemption_reason_code [String, nil] BT-121
    def initialize(rate:, taxable_amount:, tax_amount:, category: nil,
                   exemption_reason: nil, exemption_reason_code: nil)
      raise ArgumentError, Einvoicing::I18n.t("tax.invalid_rate", rate: rate) if rate.to_f.negative?

      code = Tax.category_code_for(rate: rate, category: category)
      default_code, default_reason = DEFAULT_EXEMPTIONS.fetch(code, [ nil, nil ])

      super(
        rate: rate,
        taxable_amount: taxable_amount,
        tax_amount: tax_amount,
        category: category,
        exemption_reason: exemption_reason || default_reason,
        exemption_reason_code: exemption_reason_code || default_code
      )
    end

    def category_code
      Tax.category_code_for(rate: rate, category: category)
    end

    # True when EN 16931 requires BT-120 or BT-121 on this breakdown line.
    def exemption_required?
      EXEMPTION_REQUIRED_CODES.include?(category_code)
    end

    def rate_percent
      (Tax.effective_rate(rate: rate, category: category) * 100).round(2)
    end
  end
end
