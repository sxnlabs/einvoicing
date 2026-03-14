# frozen_string_literal: true

require "spec_helper"

RSpec.describe Einvoicing::PPF::InvoiceAdapter do
  let(:seller) do
    Einvoicing::Party.new(
      name:  "Acme SAS",
      siret: "35600000000048"  # La Poste HQ — Luhn-valid SIRET
    )
  end

  let(:buyer) do
    Einvoicing::Party.new(
      name:  "Client SA",
      siret: "55203253400017"  # Renault — Luhn-valid SIRET
    )
  end

  let(:line) do
    Einvoicing::LineItem.new(
      description: "Software consulting",
      quantity:    5,
      unit_price:  200.00,
      vat_rate:    0.20
    )
  end

  let(:invoice) do
    Einvoicing::Invoice.new(
      invoice_number: "INV-2024-001",
      issue_date:     Date.new(2024, 1, 15),
      due_date:       Date.new(2024, 2, 15),
      seller:         seller,
      buyer:          buyer,
      lines:          [ line ]
    )
  end

  describe ".to_chorus_payload" do
    subject(:payload) { described_class.to_chorus_payload(invoice, id_structure_cpp: 42) }

    it "sets idStructureCPP" do
      expect(payload[:idStructureCPP]).to eq(42)
    end

    it "maps invoice_number to identifiantFactureFournisseur" do
      expect(payload[:identifiantFactureFournisseur]).to eq("INV-2024-001")
    end

    it "formats issue_date as ISO-8601 datetime" do
      expect(payload[:dateFacture]).to eq("2024-01-15T00:00:00.000+01:00")
    end

    it "formats due_date as ISO-8601 datetime" do
      expect(payload[:dateEcheancePaiement]).to eq("2024-02-15T00:00:00.000+01:00")
    end

    it "maps net_total to montantHT as float" do
      expect(payload[:montantHT]).to eq(1000.0)
    end

    it "maps tax_total to montantTVA as float" do
      expect(payload[:montantTVA]).to eq(200.0)
    end

    it "maps gross_total to montantTTC as float" do
      expect(payload[:montantTTC]).to eq(1200.0)
    end

    it "defaults currency to EUR" do
      expect(payload[:devise]).to eq("EUR")
    end

    it "maps seller SIRET" do
      expect(payload[:siretFournisseur]).to eq("35600000000048")
    end

    it "maps buyer SIRET" do
      expect(payload[:siretDestinataire]).to eq("55203253400017")
    end

    it "sets typeFacture to FACTURE" do
      expect(payload[:typeFacture]).to eq("FACTURE")
    end

    it "includes cadreFacturation" do
      expect(payload[:cadreFacturation][:codeCadreFacturation]).to eq("FACTURE_FOURNISSEUR")
    end

    it "removes nil fields (compact)" do
      expect(payload.keys).not_to include(:codeService)
      expect(payload.keys).not_to include(:numeroEngagement)
      expect(payload.keys).not_to include(:modePaiement)
    end

    context "with optional fields" do
      subject(:payload) do
        described_class.to_chorus_payload(
          invoice,
          id_structure_cpp:  42,
          code_service:      "SRV001",
          numero_engagement: "ENG-2024-001"
        )
      end

      it "includes code_service when provided" do
        expect(payload[:codeService]).to eq("SRV001")
      end

      it "includes numero_engagement when provided" do
        expect(payload[:numeroEngagement]).to eq("ENG-2024-001")
      end
    end
  end

  describe "line mapping" do
    subject(:line_payload) do
      described_class.to_chorus_payload(invoice, id_structure_cpp: 1)[:lignesPoste].first
    end

    it "sets numeroLigne to 1 for first line" do
      expect(line_payload[:numeroLigne]).to eq(1)
    end

    it "maps description to designation" do
      expect(line_payload[:designation]).to eq("Software consulting")
    end

    it "maps quantity as float" do
      expect(line_payload[:quantite]).to eq(5.0)
    end

    it "sets unite to U" do
      expect(line_payload[:unite]).to eq("U")
    end

    it "maps unit_price to prixUnitaireHT" do
      expect(line_payload[:prixUnitaireHT]).to eq(200.0)
    end

    it "maps net_amount to montantHT" do
      expect(line_payload[:montantHT]).to eq(1000.0)
    end

    it "maps vat_rate × 100 to tauxTVA" do
      expect(line_payload[:tauxTVA]).to eq(20.0)
    end

    it "computes montantTVA" do
      expect(line_payload[:montantTVA]).to eq(200.0)
    end
  end

  describe "payment mode mapping" do
    subject(:payload) { described_class.to_chorus_payload(invoice_with_payment, id_structure_cpp: 1) }

    let(:invoice_with_payment) do
      Einvoicing::Invoice.new(
        invoice_number:    "INV-2024-002",
        issue_date:        Date.new(2024, 1, 15),
        seller:            seller,
        buyer:             buyer,
        lines:             [ line ],
        payment_means_code: 30,
        iban:              "FR7630006000011234567890189",
        bic:               "BNPAFRPP"
      )
    end


    it "maps payment_means_code 30 to VIREMENT" do
      expect(payload[:modePaiement][:modePaiement]).to eq("VIREMENT")
    end

    it "includes IBAN" do
      expect(payload[:modePaiement][:iban]).to eq("FR7630006000011234567890189")
    end

    it "includes BIC" do
      expect(payload[:modePaiement][:bic]).to eq("BNPAFRPP")
    end
  end
end
