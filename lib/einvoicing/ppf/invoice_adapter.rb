# frozen_string_literal: true

module Einvoicing
  module PPF
    class InvoiceAdapter
      # Converts an Einvoicing::Invoice to a Chorus Pro SoumettreFacture payload.
      #
      # @param invoice [Einvoicing::Invoice]
      # @param id_structure_cpp [Integer] from find_structure()
      # @param code_service [String, nil] from list_services() — optional
      # @param engagement_number [String, nil] buyer PO/engagement number — optional for B2B
      def self.to_chorus_payload(invoice, id_structure_cpp:, code_service: nil, engagement_number: nil)
        {
          idStructureCPP:   id_structure_cpp,
          codeService:      code_service,
          numeroEngagement: engagement_number,
          cadreFacturation: {
            codeCadreFacturation: "FACTURE_FOURNISSEUR",
            codeServiceValideur:  nil
          },
          identifiantFactureFournisseur: invoice.invoice_number,
          dateFacture:             invoice.issue_date.strftime("%Y-%m-%dT00:00:00.000+01:00"),
          dateEcheancePaiement:    invoice.due_date&.strftime("%Y-%m-%dT00:00:00.000+01:00"),
          montantHT:               invoice.net_total.to_f,
          montantTVA:              invoice.tax_total.to_f,
          montantTTC:              invoice.gross_total.to_f,
          devise:                  invoice.currency || "EUR",
          siretFournisseur:        invoice.seller.siret,
          siretDestinataire:       invoice.buyer.siret,
          typeFacture:             "FACTURE",
          lignesPoste:             invoice.lines.map.with_index(1) { |line, i| line_to_chorus(line, i) },
          modePaiement:            chorus_payment_mode(invoice)
        }.compact
      end

      private_class_method def self.line_to_chorus(line, index)
        {
          numeroLigne:    index,
          designation:    line.description,
          quantite:       line.quantity.to_f,
          unite:          "U",
          prixUnitaireHT: line.unit_price.to_f,
          montantHT:      line.net_amount.to_f,
          tauxTVA:        (line.vat_rate * 100).to_f,
          montantTVA:     (line.net_amount * line.vat_rate).to_f.round(2)
        }
      end

      private_class_method def self.chorus_payment_mode(invoice)
        return nil unless invoice.respond_to?(:payment_means_code) && invoice.payment_means_code

        code_map = { 30 => "VIREMENT", 42 => "VIREMENT", 58 => "VIREMENT" }
        mode     = code_map[invoice.payment_means_code] || "VIREMENT"
        result   = { modePaiement: mode }
        result[:iban] = invoice.iban if invoice.respond_to?(:iban) && invoice.iban
        result[:bic]  = invoice.bic  if invoice.respond_to?(:bic)  && invoice.bic
        result
      end
    end
  end
end
