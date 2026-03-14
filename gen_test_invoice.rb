# frozen_string_literal: true
require_relative "lib/einvoicing"
require "hexapdf"

# Sandbox SIRETs from Chorus Pro qualif dataset
SELLER_SIRET = "37064704857900"
BUYER_SIRET  = "14543984084108"

pdf = HexaPDF::Document.new
page = pdf.pages.add
canvas = page.canvas
canvas.font("Helvetica", size: 12)
canvas.text("TEST-CPRO-SANDBOX-001", at: [50, 750])
canvas.text("Fournisseur #{SELLER_SIRET} - Destinataire #{BUYER_SIRET}", at: [50, 720])
io = StringIO.new
pdf.write(io)
blank_pdf = io.string

seller = Einvoicing::Party.new(
  name: "Fournisseur Test Sandbox",
  street: "1 rue de la Paix",
  city: "Paris",
  postal_code: "75001",
  country_code: "FR",
  siren: "370647048",
  siret: SELLER_SIRET,
  vat_number: "FR00370647048"
)

buyer = Einvoicing::Party.new(
  name: "Destinataire Test Sandbox",
  street: "1 avenue de la Republique",
  city: "Paris",
  postal_code: "75011",
  country_code: "FR",
  siren: "145439840",
  siret: BUYER_SIRET
)

invoice = Einvoicing::Invoice.new(
  invoice_number: "CPRO-TEST-001",
  issue_date: Date.today,
  due_date: Date.today + 30,
  seller: seller,
  buyer: buyer,
  payment_means_code: 30,
  iban: "FR7630006000011234567890189",
  lines: [
    Einvoicing::LineItem.new(
      description: "Prestation de service",
      quantity: 1,
      unit_price: 1000.0,
      vat_rate: 0.20
    )
  ],
  note: "Facture de test Chorus Pro sandbox"
)

xml = Einvoicing.xml(invoice, format: :cii)
result_pdf = Einvoicing.embed(blank_pdf, invoice)

File.write("/tmp/test-cpro-sandbox.xml", xml)
File.write("/tmp/test-cpro-sandbox.pdf", result_pdf)
puts "XML: #{xml.bytesize} bytes"
puts "PDF: #{result_pdf.bytesize} bytes"
