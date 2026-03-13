# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
