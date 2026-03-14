# frozen_string_literal: true

require "spec_helper"

RSpec.describe Einvoicing::PPF::Submitter do
  let(:client)    { instance_double(Einvoicing::PPF::Client) }
  let(:submitter) { described_class.new(client) }

  let(:buyer) do
    Einvoicing::Party.new(name: "Client SA", siret: "55203253400017")
  end

  let(:seller) do
    Einvoicing::Party.new(name: "Acme SAS", siret: "35600000000048")
  end

  let(:line) do
    Einvoicing::LineItem.new(description: "Consulting", quantity: 1, unit_price: 500.00)
  end

  let(:invoice) do
    Einvoicing::Invoice.new(
      invoice_number: "INV-2024-001",
      issue_date:     Date.new(2024, 1, 15),
      seller:         seller,
      buyer:          buyer,
      lines:          [ line ]
    )
  end

  let(:structure_response) { { "idStructureCPP" => 99 } }
  let(:submit_response)    { { "numeroFlux" => "FLUX-001", "statut" => "A_TRAITER" } }

  describe "#submit" do
    before do
      allow(client).to receive(:find_structure).with(siret: "55203253400017").and_return(structure_response)
      allow(client).to receive(:submit_invoice).and_return(submit_response)
    end

    it "calls find_structure with the buyer SIRET" do
      submitter.submit(invoice)
      expect(client).to have_received(:find_structure).with(siret: "55203253400017")
    end

    it "calls submit_invoice with a payload containing the structure ID" do
      submitter.submit(invoice)
      expect(client).to have_received(:submit_invoice).with(hash_including(idStructureCPP: 99))
    end

    it "returns the API response" do
      result = submitter.submit(invoice)
      expect(result["statut"]).to eq("A_TRAITER")
    end

    it "passes code_service to the payload when provided" do
      submitter.submit(invoice, code_service: "SRV001")
      expect(client).to have_received(:submit_invoice).with(hash_including(codeService: "SRV001"))
    end

    it "passes numero_engagement to the payload when provided" do
      submitter.submit(invoice, numero_engagement: "ENG-001")
      expect(client).to have_received(:submit_invoice).with(hash_including(numeroEngagement: "ENG-001"))
    end

    context "when the structure is nested under parametres" do
      let(:structure_response) { { "parametres" => { "idStructureCPP" => 77 } } }

      it "finds the structure ID in the nested path" do
        submitter.submit(invoice)
        expect(client).to have_received(:submit_invoice).with(hash_including(idStructureCPP: 77))
      end
    end

    context "when the buyer SIRET is not found in Chorus Pro" do
      let(:structure_response) { {} }

      it "raises ValidationError" do
        expect { submitter.submit(invoice) }
          .to raise_error(Einvoicing::PPF::ValidationError, /not found in Chorus Pro/)
      end
    end
  end
end
