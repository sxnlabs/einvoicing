# Code Review: `einvoicing` gem v0.1.0

**Reviewed:** All source files under `/Users/nathan/Workspace/Gems/einvoicing`
**Scope:** lib/, spec/, Gemfile, gemspec, scripts/, schemas/

---

## Summary

The gem is a well-structured v0.1.0 with a clean data model, working XML generators, and thoughtful API design. There are no critical security vulnerabilities. However there are significant correctness issues — particularly a broken test/implementation contract in the validator, floating-point arithmetic problems, and multiple EN 16931/CII XSD schema compliance violations in the XML generators that would cause real invoices to fail validation against the official schemas.

---

## Critical

### C1 — Test suite tests a stale version of `FR.validate`; both cannot be correct simultaneously

**File:** `spec/einvoicing/validators/fr_spec.rb` vs `lib/einvoicing/validators/fr.rb`

The spec (lines 83–143) was written against an older implementation where `FR.validate` returned `Array<String>`. The current on-disk implementation returns `Array<Hash>` with keys `{ field:, error:, message: }`. The spec uses `a_string_matching(...)` matchers directly on the error objects:

```ruby
# spec line 97
expect(errors).to include(a_string_matching(/invoice number/i))
```

This matcher will never pass against hashes. Running `bundle exec rspec` against the current implementation will produce a full spec failure in the `fr_spec.rb` describe `.validate` block. One of the two files is wrong and they are mutually contradictory.

**Fix:** Either update the spec matchers to `include(a_hash_including(message: /invoice number/i))` or revert the implementation to return strings.

---

### C2 — Floating-point arithmetic produces incorrect monetary totals

**Files:** `lib/einvoicing/line_item.rb` (lines 20–25), `lib/einvoicing/invoice.rb` (lines 51–63)

All monetary arithmetic uses Ruby `Float`. The `net_amount` method rounds to 2 decimal places per line, but `invoice.net_total` calls `lines.sum(&:net_amount)` which sums already-rounded floats. This introduces cumulative rounding error:

```ruby
# line_item.rb line 20
def net_amount
  (quantity * unit_price).round(2)
end
```

For example, 3 lines each with net_amount `0.005` round individually to `0.01` but sum to `0.03`, while the true sum before rounding is `0.015` which should round to `0.02`. In a real invoice with many lines at fractional prices this causes totals that disagree with what a validating party computes from the raw numbers. For financial software targeting a regulated mandate (French 2026), using `BigDecimal` or storing amounts as integers (cents) is required.

**Fix:** Use `BigDecimal` for all monetary calculations. Replace `Float` literals with `BigDecimal(value.to_s)` at construction time.

---

### C3 — CII XML: `ApplicableHeaderTradeAgreement` is missing `BuyerReference` (required by EN 16931 BR-10)

**File:** `lib/einvoicing/formats/cii.rb` (lines 107–118)

The XSD `HeaderTradeAgreementType` defines `BuyerReference` as the first element in the sequence. EN 16931 business rule BR-10 requires `BuyerReference` to be present when the buyer has provided one. More critically, the code places `BuyerOrderReferencedDocument` (which contains `payment_reference`) at the end of the agreement block. When `payment_reference` is meant to be a buyer order reference it is mapped to the wrong element; the `BuyerReference` field (a free-text reference on the header) is never emitted. The XSD sequence is: `BuyerReference`, `SellerTradeParty`, `BuyerTradeParty`, `...`, `BuyerOrderReferencedDocument`.

---

### C4 — CII XML: `ApplicableTradeTax` element order inside `HeaderTradeSettlement` may violate XSD sequence

**File:** `lib/einvoicing/formats/cii.rb` (lines 146–178)

The XSD sequence for `TradeTaxType` is: `CalculatedAmount`, `TypeCode`, `ExemptionReason`, `BasisAmount`, `CategoryCode`, `ExemptionReasonCode`, `TaxPointDate`, `DueDateTypeCode`, `RateApplicablePercent`. The line-level `ApplicableTradeTax` in cii.rb (lines 94–98) emits `TypeCode` → `CategoryCode` → `RateApplicablePercent` with no `CalculatedAmount` (optional, so fine), and `TypeCode` before `CategoryCode` is correct per schema. However, the reverse-charge sentinel value `-1` would emit `<ram:RateApplicablePercent>-100.00</ram:RateApplicablePercent>`, which is invalid per EN 16931 (the percent must be 0 for category AE). This needs verification against Mustang validation output.

---

## High

### H1 — `hexapdf` is a hard runtime dependency but should be optional

**File:** `einvoicing.gemspec` (line 23)

```ruby
s.add_dependency "hexapdf", "~> 1.0"
```

`hexapdf` is a substantial dependency (native extensions, openssl, bigdecimal). A user who only wants CII or UBL XML generation (no PDF embedding) is forced to install it. The `require "hexapdf"` call is already deferred inside `FacturX.embed` (facturx.rb line 32), but the gemspec declares it as an unconditional runtime dependency. The lazily-required pattern in the code is good — the gemspec should reflect the optional nature.

**Fix:** Move `hexapdf` to an optional dependency, or split into an `einvoicing-pdf` subgem, or at minimum document this overhead.

---

### H2 — `FR` module uses `include Base` inside a module, which does not work as intended

**File:** `lib/einvoicing/validators/fr.rb` (line 15)

`include Base` inside a module definition includes `Base`'s instance methods as instance methods of `FR`. But `FR` is used purely as a namespace (all methods are `def self.`). The `include Base` call adds dead instance methods to `FR`'s instance method table (`luhn_valid?`, `presence`, `format`) that are unreachable because `FR` is never instantiated. It also makes `FR.ancestors` include `Base`, which is misleading. The `Base.luhn_valid?` and `Base.presence` calls in fr.rb already correctly call them as module-level class methods.

**Fix:** Remove `include Base`. Call `Base.luhn_valid?` and `Base.presence` directly (which the code already does).

---

### H3 — `Tax#category_code` and `LineItem#tax_category_code` are inconsistent

**Files:** `lib/einvoicing/tax.rb` (lines 13–19), `lib/einvoicing/line_item.rb` (line 38–40)

`Tax#category_code` maps `rate == -1` to `"AE"` (reverse charge). But `LineItem#tax_category_code` only handles `0 → "Z"` and everything else `→ "S"`. A line item with `vat_rate: -1` would generate `CategoryCode: "S"` in the XML, contradicting the tax breakdown's `"AE"`. EN 16931 requires the line-level and header-level category codes to agree. The codes "E" (exempt), "G" (export), "O" (outside scope) are also unsupported.

**Fix:** `LineItem#tax_category_code` should use the same logic as `Tax#category_code`, ideally delegating to a shared helper.

---

### H4 — UBL generator: `BuyerReference` conditionally missing and `TaxCurrencyCode` never emitted

**File:** `lib/einvoicing/formats/ubl.rb` (lines 42–52)

Peppol BIS 3.0 Schematron rule `BR-CO-10` requires `BuyerReference` to be present when no `OrderReference` exists, and the code only adds it when `payment_reference` is present. This requires explicit handling. Additionally, `cbc:TaxCurrencyCode` is never emitted — required when currency differs from accounting currency, which can happen for non-EUR invoices.

---

### H5 — XSD schema files are excluded from the gem package

**File:** `einvoicing.gemspec` (line 20)

```ruby
s.files = Dir["lib/**/*.rb", "README.md", "CHANGELOG.md", "LICENSE"]
```

The `*.rb` glob excludes the XSD files under `lib/einvoicing/schemas/`. The roadmap explicitly mentions "full test against official XSD schemas" in v0.4, suggesting these schemas are intended to ship with the gem. They will be missing for users who install via RubyGems.

**Fix:** Add `"lib/**/*.xsd"` (and `"lib/**/*.xml"` if applicable) to the files glob.

---

### H6 — `Invoice#gross_total` uses double-rounded intermediates, violating EN 16931 BR-CO-13

**File:** `lib/einvoicing/invoice.rb` (lines 51–63)

`net_total` calls `.round(2)`, `tax_total` calls `.round(2)`, and then `gross_total` sums two already-rounded values. This can differ by ±0.01 from `lines.sum(&:gross_amount).round(2)`. The difference will cause `GrandTotalAmount` in the XML to disagree with the sum of `LineTotalAmount` + `TaxTotalAmount`, which is checked by EN 16931 business rule `BR-CO-13`.

---

## Medium

### M1 — `format_quantity` uses `v.ceil` comparison to detect integers, which is semantically wrong

**Files:** `lib/einvoicing/formats/cii.rb` (line 195), `lib/einvoicing/formats/ubl.rb` (line 187)

```ruby
def format_quantity(value)
  v = value.to_f
  v == v.ceil ? v.to_i.to_s : format("%.4f", v)
end
```

`v.ceil` and `v.floor` produce asymmetric results for negative values. Use `v % 1 == 0` for the integer check, which is symmetric and self-documenting.

---

### M2 — `XMLBuilder#tag` emits empty elements when block yields no content

**File:** `lib/einvoicing/xml_builder.rb` (lines 13–24)

When a block is given to `tag`, it always emits opening and closing tags even if the block writes nothing (e.g., all `text` calls inside return early due to nil values). This produces empty elements like `<cac:PostalAddress></cac:PostalAddress>` when all party fields are nil. This can cause validation failures in validators that treat required-but-empty elements differently from missing ones.

---

### M3 — `Invoiceable` concern hardcodes the French validator regardless of country

**File:** `lib/einvoicing/rails/concern.rb` (lines 84–96)

The `einvoicing_errors`, `einvoicing_valid?`, and `validate_einvoice!` methods hardcode `Einvoicing::Validators::FR`. A non-French user including `Invoiceable` in their model will get SIREN/SIRET validation errors that do not apply to them. The concern provides no way to configure which validator to use.

**Fix:** Add a class-level `einvoicing_validator` configuration hook, defaulting to `Einvoicing::Validators::FR`.

---

### M4 — `Tax#category_code` uses sentinel value `-1` for reverse charge, causing invalid XML output

**File:** `lib/einvoicing/tax.rb` (lines 13–19)

The `-1` → `"AE"` (reverse charge) mapping is a non-standard convention. EN 16931 uses rate `0` with category `"AE"` for reverse charge. With the current encoding, a reverse-charge line would emit `<ram:RateApplicablePercent>-100.00</ram:RateApplicablePercent>`, which is invalid per EN 16931 (the percent must be `0` for category AE).

**Fix:** Use `rate: 0, category: :reverse_charge` as the model, and emit `RateApplicablePercent` of `0` when category is AE.

---

### M5 — `Invoiceable#to_einvoice` uses `respond_to?` incorrectly for ActiveRecord models

**File:** `lib/einvoicing/rails/concern.rb` (line 54)

```ruby
due_date: respond_to?(:due_date) ? due_date : nil,
```

Since `Invoice` is an `ActiveRecord::Base` subclass, `respond_to?(:due_date)` will be true regardless of whether the column exists (AR defines methods for all defined attributes). The check conflates "method exists but returns nil" with "method does not exist". The correct guard for AR is `self.class.column_names.include?("due_date")`.

---

### M6 — Scripts directory uses invalid SIREN/SIRET numbers that fail the gem's own validator

**File:** `scripts/generate_sample.rb` (lines 16–37)

The seller uses `siren: "123456789"` and the buyer uses `siren: "987654321"`. Both fail Luhn checksum validation. If a developer runs `Einvoicing::Validators::FR.validate(invoice)` on this sample invoice they will get SIREN errors, contradicting the script's implied claim that the output is standards-compliant.

**Fix:** Use the same known-valid SIRENs from the test fixtures (`356000000`, `552032534`).

---

### M7 — `FacturX.embed` does not validate that `pdf_data` is actually a PDF

**File:** `lib/einvoicing/formats/facturx.rb` (lines 31–73)

The method accepts arbitrary binary data and passes it directly to `HexaPDF::Document.new`. If given non-PDF data, HexaPDF will raise a generic parse error with no meaningful context. A simple guard checking the `%PDF-` magic bytes would give a far clearer error message.

---

## Low

### L1 — Missing specs for `FacturX`, `XMLBuilder`, `Invoiceable`, and `Tax`

**File:** `spec/` directory

- `spec/einvoicing/formats/facturx_spec.rb` — the most complex module with PDF mutation has zero test coverage
- `spec/einvoicing/xml_builder_spec.rb` — the XML escaping logic is untested
- `spec/einvoicing/rails/concern_spec.rb`
- `spec/einvoicing/tax_spec.rb`
- No XSD schema validation spec (noted as v0.4 roadmap item)

---

### L2 — `cii_spec.rb` multiple-VAT-rates test is effectively a no-op

**File:** `spec/einvoicing/formats/cii_spec.rb` (lines 86–100)

```ruby
it "generates two ApplicableTradeTax entries in settlement" do
  count = xml.scan("ram:ApplicableTradeTax").length / 2  # computed but never asserted
  expect(xml).to include("RateApplicablePercent")        # always true for any invoice
end
```

The `count` variable is computed but never asserted against. This test provides no actual validation of multiple-rate breakdown behavior.

---

### L3 — `Gemfile.lock` should not be committed for a library gem

**File:** `Gemfile.lock`

A `Gemfile.lock` should be in `.gitignore` for a library gem (as opposed to an application). Committing it forces gem consumers to use exact dependency versions in their bundle, and it will conflict with the host application's Gemfile.lock. This is the standard Ruby gem convention (per RubyGems guidance).

**Fix:** Add `Gemfile.lock` to `.gitignore`.

---

### L4 — `require "date"` is duplicated across multiple files

**Files:** `lib/einvoicing/invoice.rb` (line 3), `lib/einvoicing/formats/cii.rb` (line 3), `lib/einvoicing/formats/ubl.rb` (line 3)

`require "date"` is idempotent so this is harmless, but only `lib/einvoicing.rb` (the entry point) needs to require it. Redundant requires in nested files add minor startup overhead and create confusion about where dependencies come from.

---

### L5 — `nokogiri` development dependency has no version constraint

**File:** `einvoicing.gemspec` (line 28)

```ruby
s.add_development_dependency "nokogiri"   # no version constraint
```

`nokogiri` is a native-extension gem with significant version history. Without a constraint, `bundle update` may silently pull in a breaking major version.

**Fix:** Add `"~> 1.16"` (current stable series).

---

### L6 — `Einvoicing::Invoiceable` namespace placement is misleading

**File:** `lib/einvoicing/rails/concern.rb` (line 41)

The module is `Einvoicing::Invoiceable` but it lives in the `rails/` subdirectory. Either the file should be at `lib/einvoicing/invoiceable.rb` or the module should be namespaced as `Einvoicing::Rails::Invoiceable`. The `isolate_namespace Einvoicing` in the engine (engine.rb line 8) may cause Zeitwerk autoloading conflicts in a Rails app that expects `rails/concern.rb` to define `Einvoicing::Rails::Concern`.

---

### L7 — `prawn` declared in both gemspec and Gemfile

**Files:** `einvoicing.gemspec` (line 30) and `Gemfile` (line 8)

`prawn` appears in both `s.add_development_dependency "prawn"` and `gem "prawn"` in the Gemfile's development group. When Bundler processes a gemspec-based Gemfile, it already includes all `add_development_dependency` entries, so the Gemfile entry is redundant.

---

### L8 — `XMLBuilder#escape` does not escape single quotes (low risk)

**File:** `lib/einvoicing/xml_builder.rb` (lines 44–50)

The `escape` method does not handle `'` → `&apos;`. Since `serialize_attrs` uses double-quote delimiters for all attributes, a single quote in an attribute value is safe in practice. If the builder is ever extended to support single-quote attribute delimiters, this would become a vulnerability. Worth noting for completeness.

---

## Standards Compliance Notes

These are observations about EN 16931 / Factur-X specification that affect overall compliance but don't map to a single code location:

**CII Profile URN mismatch:** `GUIDELINE_ID = "urn:cen.eu:en16931:2017"` is the correct base EN 16931 URN. However, for Factur-X specifically, the `ExchangedDocumentContext` should declare the Factur-X profile URN (e.g., `urn:factur-x.eu:1p0:en16931` for EN16931 profile). The `FacturX` module has `PROFILE_URN = "urn:factur-x.eu:1p0:en16931"` but the CII generator never uses it — it always emits the base EN 16931 URN regardless of whether it's being embedded in a Factur-X PDF.

**Payment means never emitted:** EN 16931 BT-81 (Payment means type code) is conditionally required when payment means information is provided. Neither the CII nor UBL generators emit `SpecifiedTradeSettlementPaymentMeans` / `cac:PaymentMeans`. This should be documented as a known limitation.

**`cbc:Name` duplication in UBL InvoiceLine:** The UBL generator emits both `cbc:Description` and `cbc:Name` with the same value (ubl.rb lines 158–159). UBL 2.1 distinguishes Description (buyer-facing description) from Name (short product name). `cbc:Name` is mandatory while `cbc:Description` is optional. Using the same value is not incorrect for v0.1 but should be addressed before production use.

---

## Priority Summary

| ID | Severity | Issue |
|----|----------|-------|
| C1 | Critical | FR validator spec/implementation contract broken — tests will fail |
| C2 | Critical | Float arithmetic produces incorrect monetary totals |
| C3 | Critical | Missing `BuyerReference` in CII `HeaderTradeAgreement` |
| C4 | Critical | Reverse-charge emits invalid `RateApplicablePercent` of -100 |
| H1 | High | `hexapdf` should be an optional dependency |
| H2 | High | `include Base` in `FR` module is a no-op and misleading |
| H3 | High | `Tax` and `LineItem` category code logic inconsistent |
| H4 | High | UBL missing `BuyerReference` (Peppol BR-CO-10) and `TaxCurrencyCode` |
| H5 | High | XSD schemas excluded from gem package |
| H6 | High | Double-rounding in `gross_total` violates EN 16931 BR-CO-13 |
| M1 | Medium | `format_quantity` uses `ceil` instead of `% 1 == 0` for integer check |
| M2 | Medium | `XMLBuilder#tag` emits empty elements when block yields nothing |
| M3 | Medium | `Invoiceable` concern hardcodes French validator |
| M4 | Medium | Sentinel value `-1` for reverse charge produces invalid XML |
| M5 | Medium | `respond_to?` incorrectly used for AR column presence check |
| M6 | Medium | Sample script uses invalid SIREN numbers |
| M7 | Medium | `FacturX.embed` missing PDF magic byte validation |
| L1 | Low | Missing specs for FacturX, XMLBuilder, Invoiceable, Tax |
| L2 | Low | Multi-VAT-rate spec is a no-op |
| L3 | Low | `Gemfile.lock` committed for a library gem |
| L4 | Low | `require "date"` duplicated across files |
| L5 | Low | `nokogiri` dev dependency lacks version constraint |
| L6 | Low | `Invoiceable` namespace placement misleading |
| L7 | Low | `prawn` duplicated in gemspec and Gemfile |
| L8 | Low | `escape` doesn't handle single quotes (low risk) |
