# einvoicing

[![Gem Version](https://badge.fury.io/rb/einvoicing.svg)](https://rubygems.org/gems/einvoicing)
[![CI](https://github.com/sxnlabs/einvoicing/actions/workflows/ci.yml/badge.svg)](https://github.com/sxnlabs/einvoicing/actions)

**EN 16931 electronic invoicing for Ruby.** Generate Factur-X (PDF/A-3 + CII XML), UBL 2.1, and CII D16B invoices. Validate French B2B compliance (SIREN, SIRET, TVA). Rails-ready.

## Why

France mandates structured e-invoicing for all B2B transactions starting **September 2026** (Ordonnance n° 2021-1190). Every invoice between French VAT-registered companies must be issued in a structured format (Factur-X, UBL, or CII) and transmitted via the PPF or a certified PDP.

This gem gives you a clean Ruby API to build compliant invoices, validate them against French rules, and produce all required output formats — without pulling in a heavy XML library.

## Features

- Generate **Factur-X** invoices (PDF/A-3b with embedded CII D16B XML)
- Generate **UBL 2.1** XML (Peppol BIS Billing 3.0)
- Generate **CII D16B** XML (EN 16931 / ZUGFeRD)
- Validate French B2B requirements: SIREN, SIRET (Luhn), TVA format, standard VAT rates
- Structured error reporting: `{ field:, error:, message: }` with i18n support (EN + FR)
- Payment means: IBAN, BIC/SWIFT, UNCL4461 type codes
- **Rails concern** (`Einvoicing::Invoiceable`) for ActiveRecord models
- Only one runtime dependency: `hexapdf` (for PDF/A-3 embedding). XML generation uses Ruby stdlib.

## Installation

```ruby
# Gemfile
gem "einvoicing"
```

```sh
bundle install
```

## Quick Start

```ruby
require "einvoicing"
require "date"

seller = Einvoicing::Party.new(
  name:         "SXN Labs",
  street:       "5 Lot Coat an Lem",
  city:         "Plouezoc'h",
  postal_code:  "29252",
  country_code: "FR",
  siren:        "898208145",
  siret:        "89820814500018",
  vat_number:   "FR46898208145",
  email:        "contact@sxnlabs.com"
)

buyer = Einvoicing::Party.new(
  name:         "Gecobat",
  street:       "12 rue du Bâtiment",
  city:         "Paris",
  postal_code:  "75001",
  country_code: "FR",
  siren:        "552032534",
  vat_number:   "FR83552032534"
)

lines = [
  Einvoicing::LineItem.new(
    description: "Développement backend — API REST (forfait)",
    quantity:    1,
    unit_price:  BigDecimal("2500.00"),
    vat_rate:    0.20
  ),
  Einvoicing::LineItem.new(
    description: "Intégration Factur-X",
    quantity:    5,
    unit_price:  BigDecimal("350.00"),
    vat_rate:    0.20
  )
]

invoice = Einvoicing::Invoice.new(
  invoice_number:     "FAC-2024-0042",
  issue_date:         Date.new(2024, 3, 15),
  due_date:           Date.new(2024, 4, 15),
  seller:             seller,
  buyer:              buyer,
  lines:              lines,
  payment_reference:  "FAC-2024-0042",
  note:               "30 jours net",
  payment_means_code: 30,
  iban:               "FR7630006000011234567890189",
  bic:                "BNPAFRPP"
)

# Totals are computed automatically (BigDecimal, no rounding errors)
invoice.net_total    # => 0.4000e4  (4000.00)
invoice.tax_total    # => 0.800e3   (800.00)
invoice.gross_total  # => 0.4800e4  (4800.00)

# Validate for French compliance
errors = Einvoicing::Validators::FR.validate(invoice)
errors.empty? # => true

# Generate CII D16B XML (Factur-X / ZUGFeRD)
xml = Einvoicing::Formats::CII.generate(invoice)
File.write("invoice.xml", xml)

# Generate UBL 2.1 XML (Peppol)
ubl = Einvoicing::Formats::UBL.generate(invoice)
File.write("invoice_ubl.xml", ubl)

# Embed CII XML into an existing PDF → Factur-X PDF/A-3
pdf_data   = File.binread("invoice.pdf")
facturx    = Einvoicing::Formats::FacturX.embed(pdf_data, xml)
File.binwrite("invoice_facturx.pdf", facturx)
```

## Validation Errors

Errors are returned as an array of hashes — no exceptions, no monkey-patching:

```ruby
errors = Einvoicing::Validators::FR.validate(invoice)
# => [
#   { field: :seller_siren, error: :siren_invalid,  message: "SIREN is invalid" },
#   { field: :invoice_number, error: :number_invalid, message: "Invoice number format is invalid" }
# ]

# Raise instead of returning
Einvoicing::Validators::FR.validate!(invoice)
# => raises Einvoicing::Validators::ValidationError on failure
```

### i18n (French messages)

The gem integrates with Rails i18n automatically. For standalone Ruby, set the locale before validating:

```ruby
require "i18n"
I18n.load_path += Dir[File.join(__dir__, "config/locales/*.yml")]
I18n.locale = :fr

errors = Einvoicing::Validators::FR.validate(invoice)
# => [{ field: :seller_siren, error: :siren_invalid, message: "Le numéro SIREN est invalide" }]
```

## Formats

### Factur-X (PDF/A-3 + CII)

The standard French hybrid format: a valid PDF that also carries machine-readable XML inside.

```ruby
xml      = Einvoicing::Formats::CII.generate(invoice)
pdf_data = File.binread("invoice.pdf")
facturx  = Einvoicing::Formats::FacturX.embed(pdf_data, xml)
File.binwrite("invoice_facturx.pdf", facturx)
```

The result is PDF/A-3b conformant with an embedded `factur-x.xml` file tagged as `AFRelationship: Data`.

### CII D16B (XML only)

```ruby
xml = Einvoicing::Formats::CII.generate(invoice)
```

Produces a `rsm:CrossIndustryInvoice` document with guideline ID `urn:cen.eu:en16931:2017`.

### UBL 2.1 (Peppol)

```ruby
ubl = Einvoicing::Formats::UBL.generate(invoice)
```

Produces a UBL 2.1 `Invoice` document with Peppol BIS Billing 3.0 customization ID.

## Rails Integration

Include `Einvoicing::Invoiceable` in your ActiveRecord model and implement three methods:

```ruby
class Invoice < ApplicationRecord
  include Einvoicing::Invoiceable

  def einvoicing_seller
    Einvoicing::Party.new(
      name:        company.name,
      siren:       company.siren,
      vat_number:  company.vat_number,
      street:      company.address_street,
      city:        company.address_city,
      postal_code: company.address_postal_code
    )
  end

  def einvoicing_buyer
    Einvoicing::Party.new(name: client.name, siren: client.siren)
  end

  def einvoicing_lines
    line_items.map do |li|
      Einvoicing::LineItem.new(
        description: li.description,
        quantity:    li.quantity,
        unit_price:  li.unit_price_excl_tax,
        vat_rate:    li.vat_rate
      )
    end
  end
end
```

Then in a controller or service:

```ruby
invoice = Invoice.find(42)

if invoice.einvoicing_valid?
  cii_xml = invoice.to_cii_xml
  ubl_xml = invoice.to_ubl_xml

  pdf_data    = invoice.pdf_attachment.download
  facturx_pdf = invoice.to_facturx(pdf_data)
else
  puts invoice.einvoicing_errors.map { |e| e[:message] }
end
```

### Custom validator

Use a different validator (e.g. for a non-French context):

```ruby
class Invoice < ApplicationRecord
  include Einvoicing::Invoiceable
  self.einvoicing_validator = Einvoicing::Validators::FR  # default; swap for your own
end
```

A custom validator is any module that responds to `.validate(invoice)` and returns `Array<Hash>`.

## Payment Means

Add IBAN, BIC, and UNCL4461 payment type code to the invoice. Both CII and UBL generators emit the appropriate elements automatically.

```ruby
invoice = Einvoicing::Invoice.new(
  # ... other fields ...
  payment_means_code: 30,               # UNCL4461: 30 = credit transfer
  iban:               "FR7630006000011234567890189",
  bic:                "BNPAFRPP"
)
```

Common `payment_means_code` values (UNCL4461):

| Code | Meaning |
|------|---------|
| 30   | Credit transfer |
| 42   | Payment to bank account |
| 58   | SEPA credit transfer |

## Requirements

- **Ruby >= 3.2** (uses `Data.define`)
- **hexapdf ~> 1.0** (runtime, for Factur-X PDF/A-3 embedding)
- **Java** (optional) — for local validation with the Mustang CLI validator

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Write tests first (`bundle exec rspec`)
4. Submit a pull request

## License

MIT — see [LICENSE](LICENSE).
