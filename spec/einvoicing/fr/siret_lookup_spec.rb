# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"

RSpec.describe Einvoicing::FR::SiretLookup do
  let(:api_url) { "https://recherche-entreprises.api.gouv.fr/search" }

  let(:success_body) do
    {
      "results" => [ {
        "nom_complet" => "SXNLABS",
        "siege" => { "siret" => "89820814500018", "adresse" => "1 RUE TEST 75001 PARIS" }
      } ]
    }.to_json
  end

  let(:empty_body) do
    { "results" => [ { "nom_complet" => nil, "siege" => { "siret" => nil, "adresse" => nil } } ] }.to_json
  end

  describe ".find" do
    it "returns siret for valid SIREN" do
      stub_request(:get, api_url).with(query: hash_including("q" => "898208145"))
        .to_return(status: 200, body: success_body, headers: { "Content-Type" => "application/json" })

      result = described_class.find("898208145")
      expect(result).to be_a(Hash)
      expect(result[:siret]).to eq("89820814500018")
    end

    it "returns nil when API returns no siret" do
      stub_request(:get, api_url).with(query: hash_including("q" => "000000000"))
        .to_return(status: 200, body: empty_body, headers: { "Content-Type" => "application/json" })

      expect(described_class.find("000000000")).to be_nil
    end

    it "returns nil for nil input" do
      expect(described_class.find(nil)).to be_nil
    end

    it "returns nil for wrong format" do
      expect(described_class.find("not-a-siren")).to be_nil
    end

    it "returns nil on HTTP error" do
      stub_request(:get, api_url).with(query: hash_including("q" => "898208145")).to_return(status: 500)
      expect(described_class.find("898208145")).to be_nil
    end
  end

  describe ".enrich!" do
    it "returns a new party with siret set" do
      stub_request(:get, api_url).with(query: hash_including("q" => "898208145"))
        .to_return(status: 200, body: success_body, headers: { "Content-Type" => "application/json" })

      party = Einvoicing::Party.new(name: "Test", siren: "898208145")
      enriched = described_class.enrich!(party)
      expect(enriched.siret).to eq("89820814500018")
    end

    it "returns party unchanged if siret already set" do
      party = Einvoicing::Party.new(name: "Test", siren: "898208145", siret: "existing000000")
      result = described_class.enrich!(party)
      expect(result.siret).to eq("existing000000")
    end

    it "returns party unchanged if siren blank" do
      party = Einvoicing::Party.new(name: "Test")
      result = described_class.enrich!(party)
      expect(result).to equal(party)
    end
  end
end
