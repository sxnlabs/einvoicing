# frozen_string_literal: true

module Einvoicing
  module Formats
    # Generates CII D16B (Cross Industry Invoice) XML compliant with EN 16931
    # and the Factur-X EN16931 profile.
    #
    # @example
    #   xml = Einvoicing::Formats::CII.generate(invoice)
    #   File.write("invoice.xml", xml)
    module CII
      GUIDELINE_ID = "urn:cen.eu:en16931:2017"

      RSM_NS = "urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100"
      RAM_NS = "urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100"
      UDT_NS = "urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100"
      QDT_NS = "urn:un:unece:uncefact:data:standard:QualifiedDataType:100"

      def self.generate(invoice, profile: :en16931)
        b = XMLBuilder.new
        b.tag(
          "rsm:CrossIndustryInvoice",
          "xmlns:rsm" => RSM_NS,
          "xmlns:ram" => RAM_NS,
          "xmlns:udt" => UDT_NS,
          "xmlns:qdt" => QDT_NS,
          "xmlns:xsi" => "http://www.w3.org/2001/XMLSchema-instance"
        ) do
          exchanged_document_context(b)
          exchanged_document(b, invoice)
          supply_chain_trade_transaction(b, invoice, profile)
        end
        b.to_xml
      end

      # -- Private helpers ---------------------------------------------------

      def self.exchanged_document_context(b)
        b.tag("rsm:ExchangedDocumentContext") do
          b.tag("ram:GuidelineSpecifiedDocumentContextParameter") do
            b.text("ram:ID", GUIDELINE_ID)
          end
        end
      end
      private_class_method :exchanged_document_context

      def self.exchanged_document(b, invoice)
        b.tag("rsm:ExchangedDocument") do
          b.text("ram:ID", invoice.invoice_number)
          b.text("ram:TypeCode", invoice.document_type == :credit_note ? "381" : "380")
          b.tag("ram:IssueDateTime") do
            b.text("udt:DateTimeString", format_date(invoice.issue_date), "format" => "102")
          end
          if invoice.document_type == :credit_note && invoice.original_invoice_number
            b.tag("ram:IncludedNote") do
              note = "Credit note for invoice #{invoice.original_invoice_number}"
              note += " dated #{invoice.original_invoice_date.strftime('%d/%m/%Y')}" if invoice.original_invoice_date
              b.text("ram:Content", note)
            end
          end
          if invoice.note
            b.tag("ram:IncludedNote") do
              b.text("ram:Content", invoice.note)
            end
          end
        end
      end
      private_class_method :exchanged_document

      def self.supply_chain_trade_transaction(b, invoice, profile)
        b.tag("rsm:SupplyChainTradeTransaction") do
          invoice.lines.each_with_index do |line, idx|
            trade_line_item(b, line, idx + 1, invoice.currency)
          end
          header_trade_agreement(b, invoice, profile)
          b.tag("ram:ApplicableHeaderTradeDelivery")
          header_trade_settlement(b, invoice)
        end
      end
      private_class_method :supply_chain_trade_transaction

      def self.trade_line_item(b, line, index, currency)
        b.tag("ram:IncludedSupplyChainTradeLineItem") do
          b.tag("ram:AssociatedDocumentLineDocument") do
            b.text("ram:LineID", index.to_s)
          end
          b.tag("ram:SpecifiedTradeProduct") do
            b.text("ram:Name", line.description)
          end
          b.tag("ram:SpecifiedLineTradeAgreement") do
            b.tag("ram:NetPriceProductTradePrice") do
              b.text("ram:ChargeAmount", format_amount(line.unit_price))
            end
          end
          b.tag("ram:SpecifiedLineTradeDelivery") do
            b.text("ram:BilledQuantity", format_quantity(line.quantity), "unitCode" => line.unit)
          end
          b.tag("ram:SpecifiedLineTradeSettlement") do
            b.tag("ram:ApplicableTradeTax") do
              b.text("ram:TypeCode", "VAT")
              b.text("ram:CategoryCode", line.tax_category_code)
              b.text("ram:RateApplicablePercent", format_amount(line.vat_rate_percent))
            end
            b.tag("ram:SpecifiedTradeSettlementLineMonetarySummation") do
              b.text("ram:LineTotalAmount", format_amount(line.net_amount))
            end
          end
        end
      end
      private_class_method :trade_line_item

      def self.header_trade_agreement(b, invoice, profile)
        b.tag("ram:ApplicableHeaderTradeAgreement") do
          # BuyerReference must be first in the sequence (EN 16931 BR-10 / XSD order).
          b.text("ram:BuyerReference", invoice.payment_reference || "")
          b.tag("ram:SellerTradeParty") { party_xml(b, invoice.seller, profile) }
          b.tag("ram:BuyerTradeParty")  { party_xml(b, invoice.buyer, profile) }
        end
      end
      private_class_method :header_trade_agreement

      def self.party_xml(b, party, profile)
        b.text("ram:Name", party.name)
        legal_id = party.siret || party.siren
        if legal_id
          b.tag("ram:SpecifiedLegalOrganization") do
            scheme = (profile == :chorus_pro && party.siret) ? "SIRET" : "0002"
            b.text("ram:ID", legal_id, "schemeID" => scheme)
          end
        end
        b.tag("ram:PostalTradeAddress") do
          b.text("ram:PostcodeCode", party.postal_code)
          b.text("ram:LineOne",      party.street)
          b.text("ram:CityName",     party.city)
          b.text("ram:CountryID",    party.country_code || "FR")
        end
        if party.email
          b.tag("ram:URIUniversalCommunication") do
            b.text("ram:URIID", party.email, "schemeID" => "EM")
          end
        end
        if party.vat_number
          b.tag("ram:SpecifiedTaxRegistration") do
            b.text("ram:ID", party.vat_number, "schemeID" => "VA")
          end
        end
      end
      private_class_method :party_xml

      def self.header_trade_settlement(b, invoice)
        b.tag("ram:ApplicableHeaderTradeSettlement") do
          b.text("ram:PaymentReference", invoice.payment_reference || invoice.invoice_number)
          b.text("ram:InvoiceCurrencyCode", invoice.currency)

          if invoice.payment_means_code
            b.tag("ram:SpecifiedTradeSettlementPaymentMeans") do
              b.text("ram:TypeCode", invoice.payment_means_code.to_s)
              if invoice.iban
                b.tag("ram:PayeePartyCreditorFinancialAccount") do
                  b.text("ram:IBANID", invoice.iban)
                end
              end
              if invoice.bic
                b.tag("ram:PayeeSpecifiedCreditorFinancialInstitution") do
                  b.text("ram:BICID", invoice.bic)
                end
              end
            end
          end

          invoice.tax_breakdown.each do |tax|
            b.tag("ram:ApplicableTradeTax") do
              b.text("ram:CalculatedAmount", format_amount(tax.tax_amount))
              b.text("ram:TypeCode", "VAT")
              b.text("ram:BasisAmount", format_amount(tax.taxable_amount))
              b.text("ram:CategoryCode", tax.category_code)
              b.text("ram:RateApplicablePercent", format_amount(tax.rate_percent))
            end
          end

          if invoice.due_date
            b.tag("ram:SpecifiedTradePaymentTerms") do
              b.tag("ram:DueDateDateTime") do
                b.text("udt:DateTimeString", format_date(invoice.due_date), "format" => "102")
              end
            end
          end

          b.tag("ram:SpecifiedTradeSettlementHeaderMonetarySummation") do
            b.text("ram:LineTotalAmount",    format_amount(invoice.net_total))
            b.text("ram:TaxBasisTotalAmount", format_amount(invoice.net_total))
            b.text("ram:TaxTotalAmount",     format_amount(invoice.tax_total),
                   "currencyID" => invoice.currency)
            b.text("ram:GrandTotalAmount",   format_amount(invoice.gross_total))
            b.text("ram:DuePayableAmount",   format_amount(invoice.due_amount))
          end
        end
      end
      private_class_method :header_trade_settlement

      # Format a Date or string as YYYYMMDD (CII date format 102).
      def self.format_date(date)
        d = date.is_a?(Date) ? date : Date.parse(date.to_s)
        d.strftime("%Y%m%d")
      end
      private_class_method :format_date

      def self.format_amount(value)
        format("%.2f", value)
      end
      private_class_method :format_amount

      def self.format_quantity(value)
        v = value.to_f
        v % 1 == 0 ? v.to_i.to_s : format("%.4f", v)
      end
      private_class_method :format_quantity
    end
  end
end
