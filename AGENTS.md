# AGENT.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## About This Project

`einvoicing` is a Ruby gem (v0.5.0) for generating and validating EN 16931-compliant electronic invoices for European markets (primary focus: French B2B mandate, September 2026). It generates Factur-X (PDF/A-3b with embedded CII XML), UBL 2.1, and CII D16B formats.

## Commands

```bash
bundle exec rspec                                          # Full test suite
bundle exec rspec spec/einvoicing/validators/fr_spec.rb   # Single file
bundle exec rspec spec/einvoicing_spec.rb:42              # Single test by line
bundle exec rspec -e "generates CII XML"                  # Single test by name
bundle exec rubocop                                        # Lint
```

## Architecture

### Core Models (`lib/einvoicing/`)
All use `Data.define` (Ruby 3.2+, immutable) with `BigDecimal` for financial calculations:
- **Invoice** — top-level aggregate; auto-computes `tax_breakdown`, `net_total`, `tax_total`, `gross_total`, `due_amount`
- **Party** — seller/buyer; resolves Peppol endpoint (SIRET → scheme 0002, fallback to email); supports `fetch_siret!` via Sirene API
- **LineItem** — description, quantity, unit_price, vat_rate; computes net/vat/gross amounts
- **Tax** — rate, taxable_amount, tax_amount, category; maps to CII/UBL tax category codes

### Format Generators (`lib/einvoicing/formats/`)
- **CII** (`cii.rb`) — CII D16B XML (CrossIndustryInvoice), EN16931 profile
- **UBL** (`ubl.rb`) — UBL 2.1 Invoice XML, Peppol BIS Billing 3.0 customization ID; handles credit notes (TypeCode 381)
- **FacturX** (`facturx.rb`) — embeds CII XML into an existing PDF using HexaPDF, producing PDF/A-3b with `factur-x.xml` as `AFRelationship:Data`

### Validators (`lib/einvoicing/validators/`)
All validators return `Array<Hash>` with `{ field:, error:, message: }` — they never raise.
- **FR** (`fr.rb`) — SIREN/SIRET format + Luhn checksum, VAT number format, IBAN/BIC, mandatory fields
- **Peppol** (`peppol.rb`) — XSLT-based Schematron validation against `PEPPOL-EN16931-UBL.xslt` (requires Java + Saxon-HE 12)

### Top-Level Facade (`lib/einvoicing.rb`)
- `Einvoicing.xml(invoice, format: :cii)` — generate XML string
- `Einvoicing.embed(pdf, invoice_or_xml)` — produce Factur-X PDF binary
- `Einvoicing.validate(invoice, market: :fr)` — returns error array
- `Einvoicing.process(...)` — combined; never raises, returns result hash

### Rails Integration
`include Einvoicing::Invoiceable` in an ActiveRecord model. Requires implementing `invoice_number`, `issue_date`, `einvoicing_seller`, `einvoicing_buyer`, `einvoicing_lines`. Provides `to_einvoice`, `to_cii_xml`, `to_ubl_xml`, `to_facturx(pdf)`, `einvoicing_valid?`, `einvoicing_errors`.

### XML Generation
Uses a custom `XMLBuilder` (no external XML library) that suppresses empty elements.

### Schemas & Assets (`lib/einvoicing/schemas/`)
Bundled XSD files for Factur-X profiles (BASIC, EN16931, EXTENDED, etc.), `srgb.icc` for PDF/A-3 conformance, and `PEPPOL-EN16931-UBL.xslt` (231KB) for Peppol validation.

### Test Fixtures
Shared fixtures are defined in `spec/spec_helper.rb` as `Fixtures.seller`, `Fixtures.buyer`, `Fixtures.line`, `Fixtures.invoice`. Seller uses La Poste SIREN (356000000, valid Luhn); buyer uses Renault SIREN (552032534).

## Key Constraints
- Ruby >= 3.2 required (`Data.define`)
- Only one runtime dependency: `hexapdf ~> 1.0`
- Peppol validation requires Java 21 + Saxon-HE 12 JAR (downloaded by CI)
- Use `BigDecimal` for all financial values — never `Float`
