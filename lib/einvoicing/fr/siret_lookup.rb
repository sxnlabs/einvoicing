# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Einvoicing
  module FR
    module SiretLookup
      API_URL = "https://recherche-entreprises.api.gouv.fr/search"

      # Find SIRET for a given SIREN using the French government Sirene API.
      # Returns { siret:, name:, address: } or nil on any error.
      def self.find(siren)
        return nil unless siren.to_s.match?(/\A\d{9}\z/)

        uri = URI(API_URL)
        uri.query = URI.encode_www_form(q: siren.to_s, mtq: "true")

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                   open_timeout: 5, read_timeout: 10) do |http|
          http.get(uri.request_uri)
        end

        return nil unless response.code == "200"

        data = JSON.parse(response.body)
        result = data["results"]&.first
        return nil unless result

        siege = result["siege"] || {}
        siret = siege["siret"]
        return nil if siret.nil? || siret.empty?

        { siret: siret, name: result["nom_complet"], address: siege["adresse"] }
      rescue StandardError
        nil
      end

      # Enrich a Party object by fetching and setting its SIRET from the API.
      # Only calls the API if party.siren is present and party.siret is blank.
      # Returns the party.
      def self.enrich!(party)
        return party if party.siren.to_s.strip.empty?
        return party if party.respond_to?(:siret) && !party.siret.to_s.strip.empty?

        result = find(party.siren.to_s.gsub(/\s/, ""))
        return party unless result&.dig(:siret)

        party.with(siret: result[:siret])
      end
    end
  end
end
