# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.9.0] - 2026-08-05

Everything here comes from a batch of 15 deliberately hostile Factur-X invoices
(multi-rate, reverse charge, 500 lines, DOM rates, foreign currency) run through
the XSD, the PDF/A-3 container checks and a hand-recomputed EN 16931 rule set.
Four of the five findings were ours.

### Added
- The full EN 16931 VAT category set (BT-118) on `LineItem`, `AllowanceCharge` and `Tax`: `:standard` (S), `:zero_rated` (Z), `:exempt` (E), `:reverse_charge` (AE), `:intra_community` (K), `:export` (G), `:not_subject` (O). An unknown category now raises instead of silently emitting `S`
- VAT exemption reason (BT-120) and reason code (BT-121), emitted as `ram:ExemptionReason` / `ram:ExemptionReasonCode` in CII and `cbc:TaxExemptionReason` / `cbc:TaxExemptionReasonCode` in UBL. AE, K, G and O default to their VATEX code (`VATEX-EU-AE`, `VATEX-EU-IC`, `VATEX-EU-G`, `VATEX-EU-O`); E takes the caller's, with `Einvoicing::Tax::VATEX_FR_FRANCHISE` provided for the art. 293 B franchise. S and Z never carry one (BR-Z-10)
- `tax_exchange_rate` on `Invoice`, plus `#tax_accounting_currency?` and `#tax_total_in_tax_currency`. When BT-6 differs from BT-5, CII now emits `ram:TaxCurrencyCode` and a second `ram:TaxTotalAmount` in the accounting currency (BT-111), and UBL a second `cac:TaxTotal` — BR-53
- `Einvoicing::Validators::FR.valid_vat_rate?`, and FR validator checks for a missing exemption reason (BR-E-10, BR-AE-10, BR-IC-10, BR-G-10, BR-O-10) and for a declared accounting currency with no exchange rate (BR-53)

### Fixed
- Each VAT category's tax amount (BT-117) is now derived from its rounded taxable base (BT-116 × BT-119) instead of summing the rounded per-line VAT. The two agree on small invoices and drift apart on large ones — a 500-line invoice was off by 3 and 15 cents on two categories, which a strict BR-S-09 check rejects outright
- The FR validator no longer rejects a counterparty's own VAT number. It now validates against the party's country (BT-40 / BT-55), with patterns for the 27 member states plus XI; every intra-Community and reverse-charge invoice used to fail on the buyer's VAT number
- The French VAT rate list now includes the rates the "20 / 10 / 5.5 / 0" shortlist leaves out: 2.1 % (press, reimbursable medicine), the DOM rates 8.5 %, 1.75 % and 1.05 %, and the Corsican rates 13 % and 0.9 %. Comparison moved to `BigDecimal` at 4 decimals so 1.05 % and 1.75 % stop colliding
- Exempt, reverse-charge and out-of-scope categories now bill 0 % whatever rate was passed in, so `RateApplicablePercent` and `CalculatedAmount` can no longer disagree
- `Invoice#with` no longer returns an invoice with a nil `tax_breakdown` on Ruby 3.2. It relied on `Data#with` calling `#initialize`, which only holds from Ruby 3.3 on; on 3.2 the members are copied straight across, so the deliberate `tax_breakdown: nil` was written as-is and every total derived from it raised `NoMethodError`. Broken since 0.8.0 for `#with(lines:)`, `#with(allowances:)` and `#with(charges:)` — the gem declares `>= 3.2`

## [0.8.1] - 2026-07-25

### Fixed
- Packaged files are no longer shipped with the maintainer's private file mode. `gem build` copies each file's mode from the working tree and git records only the executable bit, so files sitting at 0600 in a checkout shipped as 0600 and the gem failed to load for any non-root user — `cannot load such file -- .../lib/einvoicing/errors`. Affects every release built from a checkout with a restrictive umask; a spec now fails the build before such a gem can be pushed

## [0.8.0] - 2026-07-25

### Added
- Document-level allowances (BG-20) and charges (BG-21) via `Einvoicing::AllowanceCharge`, passed to `Invoice` as `allowances:` and `charges:` — emitted as `ram:SpecifiedTradeAllowanceCharge` in CII and `cac:AllowanceCharge` in UBL, with reason (BT-97/BT-104), reason code (BT-98/BT-105), base amount (BT-93/BT-100) and percentage (BT-94/BT-101)
- `Invoice#line_total` (BT-106), `#allowance_total` (BT-107) and `#charge_total` (BT-108); `#net_total` is now BT-109 (`line_total − allowance_total + charge_total`, BR-CO-13) and the VAT breakdown adjusts each category's taxable base and VAT accordingly (BR-CO-10 to BR-CO-12)
- `einvoicing_allowances` / `einvoicing_charges` hooks on `Einvoicing::Invoiceable` (both default to `[]`)
- FR validator checks on allowances and charges: non-negative amount, reason or reason code required (BR-33 / BR-38), known French VAT rate

### Fixed
- `Invoice#with` recomputes the tax breakdown when `lines`, `allowances` or `charges` change, instead of carrying the stale one over to the copy — pass `tax_breakdown:` explicitly to keep a custom breakdown

## [0.7.1] - 2026-07-16

### Fixed
- CII credit notes now emit the preceding invoice number (BT-25) and optional issue date (BT-26) as a machine-readable EN 16931 BG-3 reference while retaining the legacy human-readable note when no explicit invoice note is provided

## [0.7.0] - 2026-07-14

### Added
- `prepaid_amount` on `Invoice` (BT-113 `TotalPrepaidAmount` in CII / `PrepaidAmount` in UBL) so a retained/prepaid amount (e.g. retenue de garantie) reduces the amount due (BR-CO-16: `DuePayableAmount = GrandTotal − TotalPrepaidAmount`) without affecting the taxable base or VAT totals
- CII profile support: `:chorus_pro` and `:en16931` selectable per invoice

### Fixed
- CII `schemeID` SIRET correctly emitted for Chorus Pro
- `PaymentMeans` is now required when generating CII/UBL

## [0.6.0] - 2026-03-14

### Changed
- Codebase aligned on `rubocop-rails-omakase` standards
- Locale strings extracted into `config/locales/*.yml` (English + French)

## [0.5.0] - 2026-03-14

### Fixed
- Removed stale `spec/einvoicing/siret_lookup_spec.rb` (referenced old `Einvoicing::SiretLookup` class)
- Peppol validator spec now asserts 0 errors for a valid BIS 3.0 invoice and verifies error messages are non-empty

### Added
- `spec/einvoicing_spec.rb` — facade API specs (`Einvoicing.xml`, `.validate`, `.process`)

## [0.4.0] - 2026-03-13

### Added
- `Einvoicing.xml(invoice, format: :cii | :ubl)` — top-level XML generation
- `Einvoicing.embed(pdf, invoice_or_xml)` — top-level Factur-X embedding
- `Einvoicing.validate(invoice, market: :fr)` — top-level validation
- `Einvoicing.process(invoice, format:, market:, pdf:)` — full pipeline, never raises
- `Einvoicing::FR::SiretLookup.find(siren)` — SIRET lookup via French government API (no auth, stdlib only)
- `Einvoicing::FR::SiretLookup.enrich!(party)` — auto-fills SIRET on a Party from its SIREN
- `Einvoicing::Validators::Peppol.validate_ubl(xml)` — Peppol BIS 3.0 Schematron validation (requires Java + Saxon-HE 12)
- `Einvoicing::Errors::JavaNotFound`, `Einvoicing::Errors::ValidationError`
- `lib/einvoicing/fr.rb` — FR submodule entrypoint

## [0.3.0] - 2026-03-13

### Added
- Credit notes (`document_type: :credit_note`, TypeCode 381) in CII and UBL
- BillingReference in UBL credit notes referencing original invoice
- IBAN and BIC format validation in FR validator
- TaxCurrencyCode support in UBL for non-EUR invoices
- XSD schema validation in test suite
- BuyerReference always emitted in UBL (EN 16931 BT-10 compliance, fallback to invoice_number)

## [0.2.0] - 2026-03-13

### Added
- i18n error messages with English and French translations
- Payment means support (IBAN, BIC, payment type code) in CII and UBL
- Ruby symbol error codes in validators (`{ field:, error:, message: }`)
- Configurable validator in Invoiceable concern (`einvoicing_validator=`)
- ELI5 documentation in docs/eli5-e-invoicing.md

### Fixed
- PDF/A-3 conformance: bundled sRGB ICC profile for OutputIntent (Mustang PDF:valid)
- BigDecimal arithmetic throughout (was Float — rounding errors on financial totals)
- CII element ordering: URIUniversalCommunication before SpecifiedTaxRegistration
- Reverse charge: category: :reverse_charge instead of sentinel -1; emits RateApplicablePercent 0
- BuyerReference emitted in ApplicableHeaderTradeAgreement
- Empty XML elements suppressed by XMLBuilder
- SIREN/SIRET examples in sample script use known-valid Luhn values
- Gemfile.lock excluded from gem package

### Changed
- Validator errors now return `Array<Hash>` with `:field`, `:error`, `:message` keys
- All monetary amounts use BigDecimal (breaking change for Float inputs: wrap in BigDecimal())

## [0.1.0] - 2026-03-13

### Added
- Core invoice data model (`Invoice`, `Party`, `LineItem`, `Tax`) using Ruby 3.2 `Data.define`
- CII D16B XML generator (`Einvoicing::Formats::CII`) — EN 16931 / Factur-X EN16931 profile
- UBL 2.1 XML generator (`Einvoicing::Formats::UBL`) — EN 16931 / Peppol BIS Billing 3.0
- Factur-X embedding (`Einvoicing::Formats::FacturX`) — embeds CII XML into PDF/A-3 via hexapdf
- French validators (`Einvoicing::Validators::FR`) — SIREN, SIRET (Luhn), TVA format, invoice number
- Rails concern (`Einvoicing::Invoiceable`) — `to_cii_xml`, `to_ubl_xml`, `to_facturx`, `einvoicing_valid?`
- Rails engine (`Einvoicing::Rails::Engine`)
- Zero runtime dependencies beyond hexapdf (stdlib-only XML generation via internal builder)
- RSpec test suite

[Unreleased]: https://github.com/sxnlabs/einvoicing/compare/v0.8.1...HEAD
[0.8.1]: https://github.com/sxnlabs/einvoicing/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/sxnlabs/einvoicing/compare/v0.7.1...v0.8.0
[0.7.1]: https://github.com/sxnlabs/einvoicing/compare/v0.7.0...v0.7.1
[0.1.0]: https://github.com/sxnlabs/einvoicing/releases/tag/v0.1.0
