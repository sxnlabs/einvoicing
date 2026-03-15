# frozen_string_literal: true

module Einvoicing
  module PPF
    class Submitter
      def initialize(client)
        @client = client
      end

      # Submit an invoice to Chorus Pro / PPF.
      # Returns the submission result hash from the API.
      #
      # @param invoice [Einvoicing::Invoice]
      # @param code_service [String, nil] optional service code from list_services
      # @param engagement_number [String, nil] optional engagement number
      def submit(invoice, code_service: nil, engagement_number: nil)
        structure    = @client.find_structure(siret: invoice.buyer.siret)
        id_structure = structure["idStructureCPP"] || structure.dig("parametres", "idStructureCPP")
        raise ValidationError, "Buyer SIRET #{invoice.buyer.siret} not found in Chorus Pro" unless id_structure

        payload = InvoiceAdapter.to_chorus_payload(
          invoice,
          id_structure_cpp: id_structure,
          code_service:     code_service,
          engagement_number: engagement_number
        )

        @client.submit_invoice(payload)
      end
    end
  end
end
