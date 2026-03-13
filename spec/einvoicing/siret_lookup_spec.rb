# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"

RSpec.describe Einvoicing::SiretLookup do
  let(:api_response) do
    {
      results: [
        {
          siren:        "898208145",
          nom_complet:  "SXN LABS",
          siege: {
            siret:   "89820814500018",
            adresse: "5 LOT COAT AN LEM 29252 PLOUEZOC H"
          }
        }
      ]
    }.to_json
  end

  before do
    stub_request(:get, /recherche-entreprises\.api\.gouv\.fr/)
      .with(query: hash_including("q" => "898208145"))
      .to_return(status: 200, body: api_response, headers: { "Content-Type" => "application/json" })

    stub_request(:get, /recherche-entreprises\.api\.gouv\.fr/)
      .with(query: hash_including("q" => "000000000"))
      .to_return(status: 200, body: '{"results":[]}', headers: { "Content-Type" => "application/json" })
  end

  describe ".find" do
    it "returns a hash with siret for a valid SIREN" do
      result = described_class.find("898208145")
      expect(result).to be_a(Hash)
      expect(result[:siret]).to eq("89820814500018")
      expect(result[:name]).to eq("SXN LABS")
    end

    it "returns nil when API returns no results" do
      expect(described_class.find("000000000")).to be_nil
    end

    it "returns nil for nil input" do
      expect(described_class.find(nil)).to be_nil
    end

    it "returns nil for wrong format (too short)" do
      expect(described_class.find("12345")).to be_nil
    end

    it "returns nil for wrong format (non-numeric)" do
      expect(described_class.find("not-siren")).to be_nil
    end
  end

  describe "Party#fetch_siret!" do
    it "returns a party with siret populated" do
      party    = Einvoicing::Party.new(name: "SXN Labs", siren: "898208145")
      enriched = party.fetch_siret!
      expect(enriched.siret).to eq("89820814500018")
    end

    it "returns self unchanged when siret is already set" do
      party  = Einvoicing::Party.new(name: "Test", siren: "898208145", siret: "89820814500018")
      result = party.fetch_siret!
      expect(result).to equal(party)
    end

    it "returns self unchanged when siren is blank" do
      party  = Einvoicing::Party.new(name: "Test")
      result = party.fetch_siret!
      expect(result).to equal(party)
    end
  end
end
