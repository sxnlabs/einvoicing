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
                      :siren, :siret, :vat_number, :email) do
    def initialize(name:, street: nil, city: nil, postal_code: nil,
                   country_code: "FR", siren: nil, siret: nil,
                   vat_number: nil, email: nil)
      super
    end

    # The 9-digit SIREN derived from SIRET if siren not provided directly.
    def siren_number
      siren || (siret && siret[0, 9])
    end
  end
end
