# frozen_string_literal: true

module Einvoicing
  module Formats
    # Generates UBL 2.1 XML compliant with EN 16931 / Peppol BIS Billing 3.0.
    #
    # @example
    #   xml = Einvoicing::Formats::UBL.generate(invoice)
    #   File.write("invoice.xml", xml)
    module UBL
      CUSTOMIZATION_ID = "urn:cen.eu:en16931:2017#compliant#urn:fdc:peppol.eu:2017:poacc:billing:3.0"
      PROFILE_ID       = "urn:fdc:peppol.eu:2017:poacc:billing:01:1.0"

      UBL_NS             = "urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
      UBL_CREDIT_NOTE_NS = "urn:oasis:names:specification:ubl:schema:xsd:CreditNote-2"
      CAC_NS             = "urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
      CBC_NS             = "urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2"

      def self.generate(invoice)
        b = XMLBuilder.new
        credit_note = invoice.document_type == :credit_note
        root_ns = credit_note ? UBL_CREDIT_NOTE_NS : UBL_NS
        root_tag = credit_note ? "CreditNote" : "Invoice"
        b.tag(
          root_tag,
          "xmlns"     => root_ns,
          "xmlns:cac" => CAC_NS,
          "xmlns:cbc" => CBC_NS
        ) do
          header(b, invoice)
          supplier_party(b, invoice.seller)
          customer_party(b, invoice.buyer)
          billing_reference(b, invoice) if credit_note && invoice.original_invoice_number
          payment_means(b, invoice) if invoice.payment_means_code
          tax_total(b, invoice)
          monetary_total(b, invoice)
          invoice.lines.each_with_index do |line, idx|
            invoice_line(b, line, idx + 1, invoice.currency)
          end
        end
        b.to_xml
      end

      # -- Private helpers ---------------------------------------------------

      def self.header(b, invoice)
        b.text("cbc:CustomizationID", CUSTOMIZATION_ID)
        b.text("cbc:ProfileID",       PROFILE_ID)
        b.text("cbc:ID",              invoice.invoice_number)
        b.text("cbc:IssueDate",       format_date(invoice.issue_date))
        b.text("cbc:DueDate",         format_date(invoice.due_date)) if invoice.due_date
        b.text("cbc:InvoiceTypeCode", invoice.document_type == :credit_note ? "381" : "380")
        b.text("cbc:Note",            invoice.note) if invoice.note
        b.text("cbc:DocumentCurrencyCode", invoice.currency)
        b.text("cbc:TaxCurrencyCode", invoice.tax_currency) if invoice.tax_currency
        b.text("cbc:BuyerReference",  invoice.payment_reference || invoice.invoice_number)
      end
      private_class_method :header

      def self.supplier_party(b, party)
        b.tag("cac:AccountingSupplierParty") do
          b.tag("cac:Party") do
            endpoint_id(b, party)
            party_name(b, party)
            postal_address(b, party)
            tax_scheme(b, party)
            legal_entity(b, party)
          end
        end
      end
      private_class_method :supplier_party

      def self.customer_party(b, party)
        b.tag("cac:AccountingCustomerParty") do
          b.tag("cac:Party") do
            endpoint_id(b, party)
            party_name(b, party)
            postal_address(b, party)
            tax_scheme(b, party)
            legal_entity(b, party)
          end
        end
      end
      private_class_method :customer_party

      # Peppol BIS 3.0 requires EndpointID for both seller and buyer (R010/R020).
      # Falls back to email with scheme "EM" if no explicit endpoint_id set.
      def self.endpoint_id(b, party)
        return unless party.endpoint_id

        b.text("cbc:EndpointID", party.endpoint_id,
               "schemeID" => party.endpoint_scheme || "EM")
      end
      private_class_method :endpoint_id

      def self.party_name(b, party)
        b.tag("cac:PartyName") do
          b.text("cbc:Name", party.name)
        end
      end
      private_class_method :party_name

      def self.postal_address(b, party)
        b.tag("cac:PostalAddress") do
          b.text("cbc:StreetName",  party.street)
          b.text("cbc:CityName",    party.city)
          b.text("cbc:PostalZone",  party.postal_code)
          b.tag("cac:Country") do
            b.text("cbc:IdentificationCode", party.country_code || "FR")
          end
        end
      end
      private_class_method :postal_address

      def self.tax_scheme(b, party)
        return unless party.vat_number

        b.tag("cac:PartyTaxScheme") do
          b.text("cbc:CompanyID", party.vat_number)
          b.tag("cac:TaxScheme") { b.text("cbc:ID", "VAT") }
        end
      end
      private_class_method :tax_scheme

      def self.legal_entity(b, party)
        b.tag("cac:PartyLegalEntity") do
          b.text("cbc:RegistrationName", party.name)
          b.text("cbc:CompanyID", party.siren_number, "schemeID" => "0002") if party.siren_number
        end
      end
      private_class_method :legal_entity

      def self.tax_total(b, invoice)
        b.tag("cac:TaxTotal") do
          b.text("cbc:TaxAmount", format_amount(invoice.tax_total),
                 "currencyID" => invoice.currency)
          invoice.tax_breakdown.each do |tax|
            b.tag("cac:TaxSubtotal") do
              b.text("cbc:TaxableAmount", format_amount(tax.taxable_amount),
                     "currencyID" => invoice.currency)
              b.text("cbc:TaxAmount", format_amount(tax.tax_amount),
                     "currencyID" => invoice.currency)
              b.tag("cac:TaxCategory") do
                b.text("cbc:ID",      tax.category_code)
                b.text("cbc:Percent", format_amount(tax.rate_percent))
                b.tag("cac:TaxScheme") { b.text("cbc:ID", "VAT") }
              end
            end
          end
        end
      end
      private_class_method :tax_total

      def self.monetary_total(b, invoice)
        b.tag("cac:LegalMonetaryTotal") do
          b.text("cbc:LineExtensionAmount", format_amount(invoice.net_total),
                 "currencyID" => invoice.currency)
          b.text("cbc:TaxExclusiveAmount", format_amount(invoice.net_total),
                 "currencyID" => invoice.currency)
          b.text("cbc:TaxInclusiveAmount", format_amount(invoice.gross_total),
                 "currencyID" => invoice.currency)
          b.text("cbc:PayableAmount", format_amount(invoice.due_amount),
                 "currencyID" => invoice.currency)
        end
      end
      private_class_method :monetary_total

      def self.invoice_line(b, line, index, currency)
        b.tag("cac:InvoiceLine") do
          b.text("cbc:ID", index.to_s)
          b.text("cbc:InvoicedQuantity", format_quantity(line.quantity), "unitCode" => line.unit)
          b.text("cbc:LineExtensionAmount", format_amount(line.net_amount),
                 "currencyID" => currency)
          b.tag("cac:Item") do
            b.text("cbc:Description", line.description)
            b.text("cbc:Name",        line.description)
            b.tag("cac:ClassifiedTaxCategory") do
              b.text("cbc:ID",      line.tax_category_code)
              b.text("cbc:Percent", format_amount(line.vat_rate_percent))
              b.tag("cac:TaxScheme") { b.text("cbc:ID", "VAT") }
            end
          end
          b.tag("cac:Price") do
            b.text("cbc:PriceAmount", format_amount(line.unit_price),
                   "currencyID" => currency)
          end
        end
      end
      private_class_method :invoice_line

      def self.billing_reference(b, invoice)
        b.tag("cac:BillingReference") do
          b.tag("cac:InvoiceDocumentReference") do
            b.text("cbc:ID", invoice.original_invoice_number)
            if invoice.original_invoice_date
              b.text("cbc:IssueDate", format_date(invoice.original_invoice_date))
            end
          end
        end
      end
      private_class_method :billing_reference

      def self.payment_means(b, invoice)
        b.tag("cac:PaymentMeans") do
          b.text("cbc:PaymentMeansCode", invoice.payment_means_code.to_s)
          if invoice.iban
            b.tag("cac:PayeeFinancialAccount") do
              b.text("cbc:ID", invoice.iban)
              if invoice.bic
                b.tag("cac:FinancialInstitutionBranch") do
                  b.text("cbc:ID", invoice.bic)
                end
              end
            end
          end
        end
      end
      private_class_method :payment_means

      def self.format_date(date)
        d = date.is_a?(Date) ? date : Date.parse(date.to_s)
        d.strftime("%Y-%m-%d")
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
