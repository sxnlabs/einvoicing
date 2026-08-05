# frozen_string_literal: true

# rubocop:disable RSpec/Output
# Manual integration test for Chorus Pro (French B2G portal) submissions.
# NOT run in CI — execute manually to generate test XML/PDF for sandbox validation:
#
#   bundle exec ruby spec/integration/chorus_pro_invoice.rb
#
# Outputs:
#   /tmp/test-cpro-sandbox-chorus.xml   — CII with profile: :chorus_pro (schemeID="SIRET")
#   /tmp/test-cpro-sandbox-en16931.xml  — CII with default profile (schemeID="0002")
#   /tmp/test-cpro-sandbox.pdf          — Factur-X PDF (chorus_pro profile)

require_relative "../../lib/einvoicing"
require "hexapdf"

# Sandbox SIRETs from Chorus Pro qualif dataset
SELLER_SIRET = "37064704200008"
BUYER_SIRET  = "14543984084108"

pdf = HexaPDF::Document.new
page = pdf.pages.add
canvas = page.canvas
canvas.font("Helvetica", size: 12)
canvas.text("TEST-CPRO-SANDBOX-001", at: [ 50, 750 ])
canvas.text("Fournisseur #{SELLER_SIRET} - Destinataire #{BUYER_SIRET}", at: [ 50, 720 ])
io = StringIO.new
pdf.write(io)
blank_pdf = io.string

seller = Einvoicing::Party.new(
  name:         "Fournisseur Test Sandbox",
  street:       "1 rue de la Paix",
  city:         "Paris",
  postal_code:  "75001",
  country_code: "FR",
  siren:        "370647042",
  siret:        SELLER_SIRET,
  vat_number:   "FR68370647042"
)

buyer = Einvoicing::Party.new(
  name:         "Destinataire Test Sandbox",
  street:       "1 avenue de la Republique",
  city:         "Paris",
  postal_code:  "75011",
  country_code: "FR",
  siren:        "145439840",
  siret:        BUYER_SIRET
)

invoice = Einvoicing::Invoice.new(
  invoice_number:     "CPRO-TEST-001",
  issue_date:         Date.today,
  due_date:           Date.today + 30,
  seller:             seller,
  buyer:              buyer,
  payment_means_code: 30,
  iban:               "FR7630006000011234567890189",
  lines:              [
    Einvoicing::LineItem.new(
      description: "Prestation de service",
      quantity:    1,
      unit_price:  1000.0,
      vat_rate:    0.20
    )
  ],
  note: "Facture de test Chorus Pro sandbox"
)

# Chorus Pro profile: schemeID="SIRET" (required by PPF)
xml_chorus = Einvoicing.xml(invoice, format: :cii, profile: :chorus_pro)
File.write("/tmp/test-cpro-sandbox-chorus.xml", xml_chorus)
puts "Chorus Pro XML (schemeID=SIRET): #{xml_chorus.bytesize} bytes"

# EN 16931 default profile: schemeID="0002" (ISO 6523 / Peppol standard)
xml_en16931 = Einvoicing.xml(invoice, format: :cii, profile: :en16931)
File.write("/tmp/test-cpro-sandbox-en16931.xml", xml_en16931)
puts "EN 16931 XML (schemeID=0002):    #{xml_en16931.bytesize} bytes"

result_pdf = Einvoicing.embed(blank_pdf, xml_chorus)
File.write("/tmp/test-cpro-sandbox.pdf", result_pdf)
puts "PDF (Factur-X, chorus_pro):      #{result_pdf.bytesize} bytes"
