# frozen_string_literal: true

module Einvoicing
  # Represents a seller or buyer on an invoice.
  #
  # @example
  #   Einvoicing::Party.new(
  #     name: "Acme SAS",
  #     street: "1 rue de la Paix",
  #     city: "Paris",
  #     postal_code: "75001",
  #     country_code: "FR",
  #     siren: "123456789",
  #     vat_number: "FR12123456789"
  #   )
  Party = Data.define(:name, :street, :city, :postal_code, :country_code,
                      :siren, :siret, :vat_number, :email,
                      :endpoint_id, :endpoint_scheme) do
    def initialize(name:, street: nil, city: nil, postal_code: nil,
                   country_code: "FR", siren: nil, siret: nil,
                   vat_number: nil, email: nil,
                   endpoint_id: nil, endpoint_scheme: nil)
      # Peppol endpoint: prefer explicit endpoint_id, then SIRET (scheme 0002 = FR standard),
      # then email (scheme EM). "EM" is not in the Peppol EAS codelist so it won't pass
      # Peppol validation — callers should provide endpoint_id + endpoint_scheme explicitly
      # or ensure siret is set for French parties.
      resolved_endpoint_id = endpoint_id || siret || email
      resolved_endpoint_scheme = if endpoint_scheme
                                   endpoint_scheme
      elsif endpoint_id
                                   nil  # caller must supply scheme when explicit
      elsif siret
                                   "0002"  # SIRET scheme — Peppol EAS FR standard
      elsif email
                                   "EM"    # email fallback (not in Peppol EAS, use for non-Peppol)
      end
      super(name: name, street: street, city: city, postal_code: postal_code,
            country_code: country_code, siren: siren, siret: siret,
            vat_number: vat_number, email: email,
            endpoint_id: resolved_endpoint_id, endpoint_scheme: resolved_endpoint_scheme)
    end

    # The 9-digit SIREN derived from SIRET if siren not provided directly.
    def siren_number
      siren || (siret && siret[0, 9])
    end

    # Look up SIRET via the Sirene API and return a new Party with siret filled in.
    # No-op (returns self) if siren is blank or siret is already set.
    #
    # @return [Party] self or new Party with siret populated
    def fetch_siret!
      return self unless siren_number && siret.nil?

      result = SiretLookup.find(siren_number)
      return self unless result

      with(siret: result[:siret])
    end
  end
end
