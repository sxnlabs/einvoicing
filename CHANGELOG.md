# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/sxnlabs/einvoicing/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/sxnlabs/einvoicing/releases/tag/v0.1.0
