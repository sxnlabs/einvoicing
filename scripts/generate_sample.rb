# frozen_string_literal: true

# Script to generate a realistic French B2B Factur-X PDF invoice.
# Usage: bundle exec ruby scripts/generate_sample.rb

require_relative "../lib/einvoicing"
require "prawn"
require "prawn/table"
require "date"

OUTPUT_PATH = "/tmp/sample-invoice.pdf"
XML_PATH    = "/tmp/sample-invoice.xml"

# ── Data ─────────────────────────────────────────────────────────────────────

seller = Einvoicing::Party.new(
  name:         "SXN Labs",
  street:       "5 rue de Vendée",
  city:         "Guipavas",
  postal_code:  "29490",
  country_code: "FR",
  siren:        "356000000",        # La Poste — known-valid Luhn SIREN
  siret:        "35600000000048",   # La Poste — known-valid Luhn SIRET
  vat_number:   "FR83356000000",
  email:        "facturation@sxnlabs.com"
)

buyer = Einvoicing::Party.new(
  name:         "Gecobat",
  street:       "1 rue du Bâtiment",
  city:         "Paris",
  postal_code:  "75001",
  country_code: "FR",
  siren:        "552032534",        # SNCF — known-valid Luhn SIREN
  siret:        "55203253400010",
  vat_number:   "FR83552032534"
)

lines = [
  Einvoicing::LineItem.new(
    description: "Développement backend — API REST (forfait)",
    quantity:    1,
    unit_price:  2_500.00,
    vat_rate:    0.20
  ),
  Einvoicing::LineItem.new(
    description: "Intégration Factur-X — mise en conformité",
    quantity:    5,
    unit_price:  350.00,
    vat_rate:    0.20
  ),
  Einvoicing::LineItem.new(
    description: "Maintenance corrective mensuelle",
    quantity:    3,
    unit_price:  250.00,
    vat_rate:    0.20
  )
]

invoice = Einvoicing::Invoice.new(
  invoice_number:    "FAC-2024-0042",
  issue_date:        Date.new(2024, 3, 15),
  due_date:          Date.new(2024, 4, 15),
  currency:          "EUR",
  seller:            seller,
  buyer:             buyer,
  lines:             lines,
  payment_reference: "FAC-2024-0042",
  note:              "Conditions de paiement : 30 jours net"
)

# ── Generate CII XML ──────────────────────────────────────────────────────────

xml = Einvoicing::Formats::CII.generate(invoice)
File.write(XML_PATH, xml, encoding: "UTF-8")
puts "CII XML written to #{XML_PATH}"

# ── Generate base PDF with Prawn ──────────────────────────────────────────────

def money(amount)
  format("%.2f EUR", amount)
end

pdf = Prawn::Document.new(page_size: "A4", margin: [40, 40, 40, 40]) do |d|
  # Header
  d.font_size 20
  d.text "FACTURE", style: :bold, align: :center
  d.font_size 10
  d.move_down 10

  d.text "N° #{invoice.invoice_number}", size: 12, style: :bold
  d.text "Date : #{invoice.issue_date.strftime('%d/%m/%Y')}"
  d.text "Échéance : #{invoice.due_date.strftime('%d/%m/%Y')}"
  d.move_down 12

  # Parties
  d.float do
    d.bounding_box([0, d.cursor], width: 220) do
      d.text "ÉMETTEUR", style: :bold, size: 9
      d.text seller.name
      d.text seller.street.to_s
      d.text "#{seller.postal_code} #{seller.city}"
      d.text "SIRET : #{seller.siret}"
      d.text "TVA : #{seller.vat_number}"
    end
  end
  d.bounding_box([260, d.cursor], width: 220) do
    d.text "DESTINATAIRE", style: :bold, size: 9
    d.text buyer.name
    d.text buyer.street.to_s
    d.text "#{buyer.postal_code} #{buyer.city}"
    d.text "SIRET : #{buyer.siret}"
    d.text "TVA : #{buyer.vat_number}"
  end
  d.move_down 30

  # Line items table
  headers = ["Description", "Qté", "PU HT", "Total HT", "TVA"]
  rows = invoice.lines.map do |line|
    [
      line.description,
      line.quantity.to_s,
      money(line.unit_price),
      money(line.net_amount),
      "#{line.vat_rate_percent}%"
    ]
  end

  d.table([headers] + rows,
          cell_style: { size: 8, padding: [4, 6, 4, 6] },
          column_widths: [240, 30, 70, 70, 40],
          header: true) do
    row(0).font_style = :bold
    row(0).background_color = "DDDDDD"
  end

  d.move_down 12

  # Totals
  d.float do
    d.bounding_box([330, d.cursor], width: 180) do
      d.text "Total HT :    #{money(invoice.net_total)}", align: :right
      d.text "TVA (20%) :   #{money(invoice.tax_total)}", align: :right
      d.text "Total TTC :   #{money(invoice.gross_total)}", align: :right, style: :bold, size: 11
    end
  end

  d.move_down 40
  d.text invoice.note.to_s, size: 8, color: "555555"
  d.move_down 6
  d.text "Facture conforme à l'EN 16931 — Format Factur-X EN16931", size: 7, color: "777777", align: :center
end

pdf_bytes = pdf.render

# ── Embed CII XML → Factur-X ─────────────────────────────────────────────────

facturx_bytes = Einvoicing::Formats::FacturX.embed(pdf_bytes, xml)
File.binwrite(OUTPUT_PATH, facturx_bytes)
puts "Factur-X PDF written to #{OUTPUT_PATH}"
puts ""
puts "Invoice summary:"
puts "  Net total  : #{money(invoice.net_total)}"
puts "  Tax total  : #{money(invoice.tax_total)}"
puts "  Gross total: #{money(invoice.gross_total)}"
