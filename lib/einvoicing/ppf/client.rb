# frozen_string_literal: true

require "net/http"
require "json"

module Einvoicing
  module PPF
    class Client
      SANDBOX_OAUTH_URL = "https://sandbox-oauth.piste.gouv.fr"
      SANDBOX_API_URL   = "https://sandbox-api.piste.gouv.fr/cpro/factures"
      PROD_OAUTH_URL    = "https://oauth.piste.gouv.fr"
      PROD_API_URL      = "https://api.piste.gouv.fr/cpro/factures"

      attr_reader :sandbox

      def initialize(client_id:, client_secret:, sandbox: true)
        @client_id        = client_id
        @client_secret    = client_secret
        @sandbox          = sandbox
        @token            = nil
        @token_expires_at = nil
      end

      # Returns current access token, refreshing if expired.
      def access_token
        refresh_token! if token_expired?
        @token
      end

      # POST /v1/rechercher/structure — find structure by SIRET, returns idStructureCPP.
      def find_structure(siret:)
        post("/v1/rechercher/structure", { siret: siret })
      end

      # POST /v1/consulter/structure — get mandatory params (engagement, service codes).
      def get_structure(id_structure_cpp:)
        post("/v1/consulter/structure", { idStructureCPP: id_structure_cpp })
      end

      # POST /v1/rechercher/service/structure — list active services for a structure.
      def list_services(id_structure_cpp:, page: 1)
        post("/v1/rechercher/service/structure", {
          idStructureCPP: id_structure_cpp,
          pageResultat:   page
        })
      end

      # POST /v1/soumettre/factures — submit an invoice.
      # invoice_hash: Hash matching the Chorus Pro invoice schema.
      def submit_invoice(invoice_hash)
        post("/v1/soumettre/factures", invoice_hash)
      end

      private

      def base_url
        sandbox ? SANDBOX_API_URL : PROD_API_URL
      end

      def oauth_url
        sandbox ? SANDBOX_OAUTH_URL : PROD_OAUTH_URL
      end

      def token_expired?
        @token.nil? || @token_expires_at.nil? || Time.now >= @token_expires_at
      end

      def refresh_token!
        uri = URI("#{oauth_url}/api/oauth/token")
        req = Net::HTTP::Post.new(uri)
        req.set_form_data(
          grant_type:    "client_credentials",
          client_id:     @client_id,
          client_secret: @client_secret,
          scope:         "openid"
        )
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
        raise AuthenticationError, "OAuth token request failed: #{res.code} #{res.body}" unless res.is_a?(Net::HTTPSuccess)

        data = JSON.parse(res.body)
        @token            = data["access_token"]
        @token_expires_at = Time.now + data.fetch("expires_in", 3600).to_i - 60
      end

      def post(path, body)
        uri = URI("#{base_url}#{path}")
        req = Net::HTTP::Post.new(uri)
        req["Authorization"] = "Bearer #{access_token}"
        req["Content-Type"]  = "application/json;charset=UTF-8"
        req["Accept"]        = "application/json"
        req.body = body.to_json
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
        handle_response(res)
      end

      def handle_response(res)
        body = begin
          JSON.parse(res.body)
        rescue StandardError
          res.body
        end
        case res
        when Net::HTTPSuccess
          body
        when Net::HTTPUnauthorized
          raise AuthenticationError, "Unauthorized: #{body}"
        when Net::HTTPForbidden
          raise AuthorizationError, "Forbidden: #{body}"
        when Net::HTTPNotFound
          raise NotFoundError, "Not found: #{body}"
        else
          raise APIError, "API error #{res.code}: #{body}"
        end
      end
    end
  end
end
