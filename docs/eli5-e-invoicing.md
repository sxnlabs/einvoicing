# E-Invoicing, Explained Simply

> What is this gem doing and why? A plain-language guide for developers who want to understand the context before reading the API docs.

---

## The short version

E-invoicing is sending invoices as **structured data** instead of PDFs that humans have to read. Governments want this so they can automatically check you paid the right VAT. The EU made a standard for what that data must look like. This gem produces invoices that match that standard.

---

## Why does this exist?

Traditionally, you send a client a PDF invoice. A human reads it, types the numbers into their accounting software, and eventually pays. Every step is manual and error-prone.

Governments noticed that a lot of VAT goes unpaid — either by mistake or on purpose. Their fix: require businesses to send invoices as machine-readable files that go through a government-controlled platform. The platform checks the invoice instantly. No more "I never received it" or "I misread the VAT amount."

**France** makes this mandatory starting in 2026 for all B2B invoices. Other EU countries have similar timelines. The EU set a shared standard so an invoice created in France can be read by software in Germany or Spain.

---

## The formats: what are CII and UBL?

Two XML formats carry the invoice data. Think of them as two different but equally valid ways to write the same thing.

**CII** (Cross-Industry Invoice) — developed by the UN. Used by France (Factur-X), Germany (ZUGFeRD), and others. Think of it as the European default.

**UBL** (Universal Business Language) — developed by OASIS. Used by Peppol (the pan-European e-invoicing network) and countries like the UK, Netherlands, and Scandinavia.

Both express the same information: who is selling, who is buying, what was sold, how much it costs, how much VAT is owed. They just use different XML tags.

---

## What is Factur-X?

Factur-X is the French (and German, where it's called ZUGFeRD) format for e-invoicing. The clever part: **it's a normal PDF that also contains the XML inside it**.

- A human opens the PDF → sees a normal invoice, prints it if they want
- Software reads the PDF → extracts the embedded XML, processes it automatically

This hybrid approach means businesses don't need to change how they communicate with clients who aren't ready for full electronic invoicing. The PDF looks the same. The machine-readable data is just hiding inside.

The gem's `FacturX.embed` method does exactly this — it takes a regular PDF and an XML document, and stitches them together into a Factur-X file.

---

## What is PDF/A-3?

Regular PDFs can reference external fonts, link to URLs, or embed JavaScript. That's fine for everyday use, but terrible for archiving — open the file in 10 years and external resources might be gone.

**PDF/A** is the archival version of PDF. It requires everything to be self-contained: fonts embedded, no external references, no JavaScript. The `/A-3` variant specifically allows embedding non-PDF files (like our XML) inside the PDF.

Factur-X requires PDF/A-3 so that the invoice is both human-readable and legally archivable. That's why the gem bundles an ICC color profile (`srgb.icc`) — PDF/A-3 requires declaring exactly what color space is used, even for a plain black-and-white invoice.

---

## What is EN 16931?

The EU regulation that defines the **core data model** for electronic invoices. It says: an invoice must have an invoice number, an issue date, a seller, a buyer, line items with descriptions and amounts, and VAT breakdowns. It doesn't care whether you use CII or UBL — both can express this model.

EN 16931 also defines business rules. For example:
- The sum of line totals must equal the invoice total (BR-CO-13)
- VAT must be calculated correctly (BR-CO-16)
- A seller in the EU must have a VAT number (BR-S-02)

The gem validates invoices against these rules before generating XML.

---

## What is SIREN / SIRET / TVA?

These are French business identifiers. Every French company has all three.

**SIREN** — 9-digit company ID. Uniquely identifies the legal entity. Think of it as a company's national ID number. Uses a Luhn checksum (same algorithm as credit cards) so typos are caught.

**SIRET** — 14-digit establishment ID. SIREN (9 digits) + NIC (5 digits identifying a specific office or warehouse). A company with multiple locations has one SIREN and multiple SIRETs.

**Numéro TVA intracommunautaire** — EU VAT number. Format: `FR` + 2-digit key + SIREN. The 2-digit key is computed from the SIREN: `(12 + 3 × (SIREN mod 97)) mod 97`. French law requires this on every B2B invoice.

The gem validates all three on French invoices so you catch mistakes before sending to the government platform.

---

## The government platform (PPF / PDP)

In France, B2B invoices above a certain threshold must transit through either:

- **PPF** (Portail Public de Facturation) — the free government platform
- **PDP** (Plateforme de Dématérialisation Partenaire) — certified private operators (like Chorus Pro competitors)

The gem handles generating the compliant XML. Transmitting it to PPF via their PISTE API is planned for a future version.

---

## BigDecimal: why not just use floats?

Floats are approximations. `0.1 + 0.2` in Ruby gives `0.30000000000000004`.

For financial software, this is a compliance problem. If your invoice says 100 lines at €10.50 each, the total must be exactly €1,050.00. If floating-point rounding produces €1,049.9999999999999, the government validator will reject it.

The gem uses `BigDecimal` for all monetary arithmetic. It's slower but exact. All amounts round at the end using banker's rounding (`.round(2, :half_up)`), not at intermediate steps.

---

## The validation flow

When you call `Einvoicing::Validators::FR.validate(invoice)`:

1. **Presence checks** — invoice number, dates, parties, at least one line item
2. **SIREN Luhn** — 9 digits, checksum valid
3. **SIRET** — 14 digits, first 9 match the SIREN
4. **TVA number** — FR + computed 2-digit key + SIREN
5. **VAT rates** — only French legal rates: 20%, 10%, 5.5%, 2.1%, 0%
6. **Amount consistency** — totals add up correctly

Errors come back as structured hashes:
```ruby
{ field: :seller_siren, error: :siren_invalid, message: "SIREN must be 9 digits (Luhn check failed)" }
```

The `field` and `error` keys are symbols — use them in code. The `message` key is human-readable and uses i18n (English by default, French available).

---

## Quick mental model

```
Your invoice data
      │
      ▼
Einvoicing::Invoice (BigDecimal amounts, validated parties)
      │
      ├─► Validators::FR.validate → errors or []
      │
      ├─► Formats::CII.generate  → XML string (Factur-X format)
      │
      ├─► Formats::UBL.generate  → XML string (Peppol format)
      │
      └─► Formats::FacturX.embed(pdf, xml) → PDF/A-3 binary
                                              (XML hidden inside)
```

The PDF/A-3 output is what you send to your client and archive. The XML inside is what the government platform reads.

---

## Glossary

| Term | Plain English |
|------|--------------|
| CII | XML format for invoices, EU standard |
| UBL | XML format for invoices, Peppol standard |
| Factur-X | PDF with XML inside, French standard |
| ZUGFeRD | Same as Factur-X but German name |
| PDF/A-3 | Archival PDF that can contain attachments |
| EN 16931 | EU data model standard for invoices |
| Peppol | Pan-European e-invoicing network |
| PPF | French government invoice portal |
| PDP | Certified private invoice operator |
| SIREN | 9-digit French company ID |
| SIRET | 14-digit French establishment ID |
| TVA intra | FR + 11-digit EU VAT number |
| Mustang | Open-source validator for Factur-X/ZUGFeRD |
