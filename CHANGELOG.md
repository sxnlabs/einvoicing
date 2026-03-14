# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[Unreleased]: https://github.com/sxnlabs/einvoicing/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/sxnlabs/einvoicing/releases/tag/v0.1.0
