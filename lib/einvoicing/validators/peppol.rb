# frozen_string_literal: true

require "open3"
require "tempfile"
require "net/http"
require "uri"

module Einvoicing
  module Validators
    # Validates UBL 2.1 invoices against Peppol BIS Billing 3.0 Schematron rules
    # using Saxon-HE via the system Java runtime.
    #
    # Requirements:
    #   - Java in PATH
    #   - Saxon-HE 12 CLI jar (auto-downloaded to /tmp/saxon-he.jar on first use)
    #   - Peppol XSLT (bundled at lib/einvoicing/data/; auto-downloaded on first use)
    #
    # @example
    #   errors = Einvoicing::Validators::Peppol.validate_ubl(xml_string)
    #   errors #=> [] when valid, or [{ field:, error:, message: }] when invalid
    module Peppol
      XSLT_URL  = "https://github.com/OpenPEPPOL/peppol-bis-invoice-3/releases/download/3.0.21/PEPPOL-EN16931-UBL.xslt"
      SAXON_URL = "https://repo1.maven.org/maven2/net/sf/saxon/Saxon-HE/10.9/Saxon-HE-10.9.jar"
      SAXON_JAR = "/tmp/saxon-he.jar"
      XSLT_PATH = File.expand_path("../data/PEPPOL-EN16931-UBL.xslt", __dir__)

      # Validate a UBL 2.1 XML string against Peppol BIS 3.0 rules.
      #
      # @param xml_string [String] UBL 2.1 invoice XML
      # @return [Array<Hash>] errors — empty array means valid
      # @raise [Einvoicing::Errors::JavaNotFound] if java is not in PATH
      # @raise [Einvoicing::Errors::ValidationError] if Saxon fails unexpectedly
      def self.validate_ubl(xml_string)
        ensure_java!
        ensure_saxon!
        ensure_xslt!

        svrl = run_saxon(xml_string)
        parse_svrl(svrl)
      end

      def self.java_available?
        _, _, status = Open3.capture3("java -version")
        status.success?
      end

      def self.ensure_java!
        raise Einvoicing::Errors::JavaNotFound, "java not found in PATH" unless java_available?
      end
      private_class_method :ensure_java!

      def self.ensure_saxon!
        return if File.exist?(SAXON_JAR)

        download(SAXON_URL, SAXON_JAR)
        return if File.exist?(SAXON_JAR)

        raise Einvoicing::Errors::ValidationError,
              "Saxon JAR not available. Download from #{SAXON_URL} and place at #{SAXON_JAR}"
      end
      private_class_method :ensure_saxon!

      def self.ensure_xslt!
        return if File.exist?(XSLT_PATH) && File.size(XSLT_PATH) > 100

        download(XSLT_URL, XSLT_PATH)
        return if File.exist?(XSLT_PATH) && File.size(XSLT_PATH) > 100

        raise Einvoicing::Errors::ValidationError,
              "Peppol XSLT not available at #{XSLT_PATH}. Download from #{XSLT_URL}"
      end
      private_class_method :ensure_xslt!

      def self.download(url, dest)
        uri = URI(url)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                        open_timeout: 30, read_timeout: 120) do |http|
          res = http.get(uri.request_uri)
          return unless res.is_a?(Net::HTTPSuccess)

          File.binwrite(dest, res.body)
        end
      rescue StandardError
        nil # caller checks if file exists
      end
      private_class_method :download

      def self.run_saxon(xml_string)
        input  = Tempfile.new(["peppol-input",  ".xml"])
        output = Tempfile.new(["peppol-output", ".svrl"])

        begin
          input.write(xml_string)
          input.close
          output.close

          cmd = ["java", "-jar", SAXON_JAR,
                 "-s:#{input.path}",
                 "-xsl:#{XSLT_PATH}",
                 "-o:#{output.path}"]

          _, stderr, status = Open3.capture3(*cmd)

          unless status.success?
            raise Einvoicing::Errors::ValidationError,
                  "Saxon failed (exit #{status.exitstatus}): #{stderr.strip}"
          end

          File.read(output.path)
        ensure
          input.unlink
          output.unlink
        end
      end
      private_class_method :run_saxon

      def self.parse_svrl(svrl_xml)
        require "rexml/document"

        doc    = REXML::Document.new(svrl_xml)
        errors = []
        ns     = { "svrl" => "http://purl.oclc.org/dsdl/svrl" }

        REXML::XPath.each(doc, "//svrl:failed-assert", ns) do |node|
          # Message is in <svrl:text> child, not in node.text directly
          text_el = node.elements["svrl:text"]
          message = text_el ? text_el.text.to_s.strip : node.text.to_s.strip

          errors << {
            field:   node.attributes["id"] || node.attributes["location"] || "",
            error:   node.attributes["test"] || "",
            message: message
          }
        end

        errors
      end
      private_class_method :parse_svrl
    end
  end
end
