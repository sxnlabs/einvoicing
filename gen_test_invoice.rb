# frozen_string_literal: true

require_relative "lib/einvoicing"
require "hexapdf"

# Create a minimal blank PDF
pdf = HexaPDF::Document.new
page = pdf.pages.add
canvas = page.canvas
canvas.font("Helvetica", size: 12)
canvas.text("TEST-CPRO-001 - Test Chorus Pro", at: [ 50, 750 ])
canvas.text("SXN Labs - DGFiP - 100.00 EUR HT + TVA 20%", at: [ 50, 720 ])
io = StringIO.new
pdf.write(io)
blank_pdf = io.string

seller = Einvoicing::Party.new(
  name: "SXN Labs",
  street: "Île Longue",
  city: "Crozon",
  postal_code: "29160",
  country_code: "FR",
  siren: "356000000",
  siret: "35600000000048",
  vat_number: "FR83356000000"
)

buyer = Einvoicing::Party.new(
  name: "Direction Generale des Finances Publiques",
  street: "139 rue de Bercy",
  city: "Paris",
  postal_code: "75012",
  country_code: "FR",
  siren: "110002017",
  siret: "11000201700241"
)

invoice = Einvoicing::Invoice.new(
  invoice_number: "TEST-CPRO-001",
  issue_date: Date.today,
  due_date: Date.today + 30,
  seller: seller,
  buyer: buyer,
  lines: [
    Einvoicing::LineItem.new(
      description: "Developpement logiciel",
      quantity: 1,
      unit_price: 100.0,
      vat_rate: 0.20
    )
  ],
  note: "Test Chorus Pro sandbox submission"
)

xml = Einvoicing.xml(invoice, format: :cii)
result_pdf = Einvoicing.embed(blank_pdf, invoice)

File.write("/tmp/test-cpro.xml", xml)
File.write("/tmp/test-cpro.pdf", result_pdf)
puts "XML: #{xml.bytesize} bytes"
puts "PDF: #{result_pdf.bytesize} bytes"
puts "Done"
