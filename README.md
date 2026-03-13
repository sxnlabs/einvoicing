# einvoicing

EU electronic invoicing for Ruby — EN 16931, Factur-X (PDF/A-3 + CII XML), UBL 2.1, and French B2B compliance.

Targets the **French September 2026 e-invoicing mandate** for SMEs and micro-enterprises.

## Features

- Generate **Factur-X** invoices (PDF/A-3 with embedded CII D16B XML)
- Generate **UBL 2.1** XML (Peppol BIS Billing 3.0)
- Generate **CII D16B** XML (EN 16931 compliant)
- Validate French B2B requirements: **SIREN, SIRET** (Luhn), **TVA** format
- Rails **`Invoiceable` concern** for ActiveRecord models
- Minimal dependencies: only `hexapdf` for PDF/A-3 embedding; everything else is Ruby stdlib

## Requirements

- Ruby >= 3.2
- `hexapdf` >= 1.0 (for Factur-X PDF embedding)

## Installation

```ruby
# Gemfile
gem 'einvoicing'
```

```sh
bundle install
```

## Quick Start

### Standalone Ruby

```ruby
require 'einvoicing'

seller = Einvoicing::Party.new(
  name:        "Acme SAS",
  street:      "1 rue de la Paix",
  city:        "Paris",
  postal_code: "75001",
  country_code: "FR",
  siren:       "356000000",
  vat_number:  "FR83356000000"
)

buyer = Einvoicing::Party.new(
  name:  "Client SA",
  siren: "552032534"
)

lines = [
  Einvoicing::LineItem.new(
    description: "Software consulting — January 2024",
    quantity:    10,
    unit_price:  150.00,
    vat_rate:    0.20   # 20%
  )
]

invoice = Einvoicing::Invoice.new(
  invoice_number: "INV-2024-001",
  issue_date:     Date.new(2024, 1, 31),
  due_date:       Date.new(2024, 2, 29),
  seller:         seller,
  buyer:          buyer,
  lines:          lines
)

# Totals (all computed automatically)
invoice.net_total    # => 1500.00
invoice.tax_total    # => 300.00
invoice.gross_total  # => 1800.00

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

# Validate for French compliance
errors = Einvoicing::Validators::FR.validate(invoice)
errors.empty? # => true
```

### Rails Integration

```ruby
# Gemfile
gem 'einvoicing'
```

```ruby
# app/models/invoice.rb
class Invoice < ApplicationRecord
  include Einvoicing::Invoiceable

  # Required: map your model's data to Einvoicing data objects

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
    Einvoicing::Party.new(
      name:  client.name,
      siren: client.siren
    )
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

```ruby
# Controller or service
invoice = Invoice.find(42)

# Validate before generating
unless invoice.einvoicing_valid?
  raise "Invalid: #{invoice.einvoicing_errors.join(', ')}"
end

# Generate formats
cii_xml = invoice.to_cii_xml
ubl_xml = invoice.to_ubl_xml

# Embed into PDF (e.g. from ActiveStorage or Prawn)
pdf_data    = invoice.pdf_attachment.download
facturx_pdf = invoice.to_facturx(pdf_data)
```

## French Compliance

The `Einvoicing::Validators::FR` module validates:

| Check | Rule |
|-------|------|
| Invoice number | 1–35 alphanumeric/dash/slash chars |
| SIREN | 9 digits, Luhn checksum |
| SIRET | 14 digits, Luhn checksum |
| TVA number | `FR` + 2 alphanumeric chars + 9-digit SIREN |
| VAT rates | 0%, 5.5%, 10%, or 20% (standard French rates) |
| Line items | At least one, with description and positive quantity |

```ruby
errors = Einvoicing::Validators::FR.validate(invoice)   # => []
Einvoicing::Validators::FR.validate!(invoice)           # raises ValidationError on failure

Einvoicing::Validators::FR.valid_siren?("356000000")    # => true
Einvoicing::Validators::FR.valid_siret?("35600000000048") # => true
Einvoicing::Validators::FR.valid_vat_number?("FR83356000000") # => true
```

## Supported Profiles

| Profile | Format | Standard |
|---------|--------|----------|
| Factur-X EN16931 | PDF/A-3 + CII D16B | EN 16931 |
| Peppol BIS Billing 3.0 | UBL 2.1 | EN 16931 |
| CII D16B | XML | EN 16931 |

## Roadmap

- **v0.1** (now) — Core data model, CII/UBL generators, Factur-X embedding, FR validators
- **v0.2** — PPF/PDP transmission via PISTE OAuth2, invoice lifecycle tracking
- **v0.3** — Peppol access point integration, DE/XRechnung support
- **v0.4** — Rails generators (install, migration), full test against official XSD schemas

## Regulatory Context

French e-invoicing becomes mandatory for SMEs and micro-enterprises in **September 2026** (Ordonnance n° 2021-1190). All invoices between French VAT-registered companies must be:
1. Issued in a structured format (Factur-X, UBL, or CII)
2. Transmitted via the PPF (Portail Public de Facturation) or a certified PDP

## Contributing

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Write tests first
4. Submit a pull request

## License

MIT — see [LICENSE](LICENSE).
