# frozen_string_literal: true

module Einvoicing
  module Formats
    # Embeds a CII XML document into an existing PDF to produce a Factur-X
    # PDF/A-3 file. Requires the `hexapdf` gem.
    #
    # The embedded file is named "factur-x.xml" and tagged as the primary
    # associated file (AFRelationship: Data).  XMP metadata is updated to
    # declare PDF/A-3b conformance and the Factur-X extension schema.
    #
    # @example
    #   pdf_bytes = File.binread("invoice.pdf")
    #   xml       = Einvoicing::Formats::CII.generate(invoice)
    #   result    = Einvoicing::Formats::FacturX.embed(pdf_bytes, xml)
    #   File.binwrite("invoice_facturx.pdf", result)
    module FacturX
      FILENAME         = "factur-x.xml"
      CONFORMANCE      = "EN 16931"
      PROFILE_URN      = "urn:factur-x.eu:1p0:en16931"
      FX_NAMESPACE     = "urn:factur-x:pdfa:CrossIndustryDocument:invoice:1p0#"
      FX_PREFIX        = "fx"
      MIME_TYPE        = "text/xml"
      DATA_DIR         = File.expand_path("../data", __dir__)

      # Embed CII XML into a PDF binary and return the Factur-X PDF binary.
      #
      # @param pdf_data [String] binary PDF content
      # @param xml_string [String] CII XML string (UTF-8)
      # @param profile [String] Factur-X profile label (default: "EN 16931")
      # @return [String] binary Factur-X PDF/A-3 content
      def self.embed(pdf_data, xml_string, profile: CONFORMANCE)
        unless pdf_data.to_s.b.start_with?("%PDF-")
          raise ArgumentError, "pdf_data does not appear to be a valid PDF (missing %PDF- magic bytes)"
        end

        require "hexapdf"

        io  = StringIO.new(pdf_data.dup.force_encoding("BINARY"))
        doc = HexaPDF::Document.new(io: io)

        xml_bytes = xml_string.encode("UTF-8").b

        # 1. Embed the XML as an embedded file stream.
        ef_stream = doc.add({
          Type:    :EmbeddedFile,
          Subtype: :"text#2Fxml",
          Params:  { Size: xml_bytes.bytesize, CheckSum: md5(xml_bytes) }
        })
        ef_stream.set_filter(:FlateDecode)
        ef_stream.stream = xml_bytes

        filespec = doc.add({
          Type: :Filespec,
          F:    FILENAME,
          UF:   FILENAME,
          AFRelationship: :Data,
          Desc: "Factur-X invoice",
          EF:   { F: ef_stream, UF: ef_stream }
        })

        # 2. Register in the EmbeddedFiles name tree.
        doc.catalog[:Names] ||= doc.add({})
        names_dict = doc.catalog[:Names]
        names_dict[:EmbeddedFiles] ||= doc.add({ Names: [] })
        names_dict[:EmbeddedFiles][:Names] << FILENAME << filespec

        # 3. Set AF array on the catalog.
        doc.catalog[:AF] = [filespec]

        # 4. Add OutputIntent (required for PDF/A-3 conformance).
        add_output_intent(doc)

        # 5. Update XMP metadata.
        update_xmp(doc, profile)

        # 6. Write back to binary string.
        out = StringIO.new("".b)
        doc.write(out)
        out.string
      end

      private_class_method def self.update_xmp(doc, profile)
        raw_xmp = build_xmp(profile)

        # HexaPDF stores XMP in the document's metadata stream.
        meta = doc.catalog[:Metadata]
        if meta
          meta.stream = raw_xmp
        else
          meta = doc.add({ Type: :Metadata, Subtype: :XML })
          meta.stream = raw_xmp
          doc.catalog[:Metadata] = meta
        end
      end

      # rubocop:disable Metrics/MethodLength
      private_class_method def self.build_xmp(profile)
        <<~XMP
          <?xpacket begin="\xEF\xBB\xBF" id="W5M0MpCehiHzreSzNTczkc9d"?>
          <x:xmpmeta xmlns:x="adobe:ns:meta/">
            <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
              <rdf:Description rdf:about=""
                xmlns:pdfaid="http://www.aiim.org/pdfa/ns/id/"
                xmlns:#{FX_PREFIX}="#{FX_NAMESPACE}">
                <pdfaid:part>3</pdfaid:part>
                <pdfaid:conformance>B</pdfaid:conformance>
                <#{FX_PREFIX}:DocumentType>INVOICE</#{FX_PREFIX}:DocumentType>
                <#{FX_PREFIX}:DocumentFileName>#{FILENAME}</#{FX_PREFIX}:DocumentFileName>
                <#{FX_PREFIX}:Version>1.0</#{FX_PREFIX}:Version>
                <#{FX_PREFIX}:ConformanceLevel>#{profile}</#{FX_PREFIX}:ConformanceLevel>
              </rdf:Description>
              <rdf:Description rdf:about=""
                xmlns:pdfaExtension="http://www.aiim.org/pdfa/ns/extension/"
                xmlns:pdfaSchema="http://www.aiim.org/pdfa/ns/schema#"
                xmlns:pdfaProperty="http://www.aiim.org/pdfa/ns/property#">
                <pdfaExtension:schemas>
                  <rdf:Bag>
                    <rdf:li rdf:parseType="Resource">
                      <pdfaSchema:schema>Factur-X PDFA Extension Schema</pdfaSchema:schema>
                      <pdfaSchema:namespaceURI>#{FX_NAMESPACE}</pdfaSchema:namespaceURI>
                      <pdfaSchema:prefix>#{FX_PREFIX}</pdfaSchema:prefix>
                      <pdfaSchema:property>
                        <rdf:Seq>
                          <rdf:li rdf:parseType="Resource">
                            <pdfaProperty:name>DocumentFileName</pdfaProperty:name>
                            <pdfaProperty:valueType>Text</pdfaProperty:valueType>
                            <pdfaProperty:category>external</pdfaProperty:category>
                            <pdfaProperty:description>The name of the embedded XML invoice file</pdfaProperty:description>
                          </rdf:li>
                          <rdf:li rdf:parseType="Resource">
                            <pdfaProperty:name>DocumentType</pdfaProperty:name>
                            <pdfaProperty:valueType>Text</pdfaProperty:valueType>
                            <pdfaProperty:category>external</pdfaProperty:category>
                            <pdfaProperty:description>The type of the hybrid document (INVOICE)</pdfaProperty:description>
                          </rdf:li>
                          <rdf:li rdf:parseType="Resource">
                            <pdfaProperty:name>Version</pdfaProperty:name>
                            <pdfaProperty:valueType>Text</pdfaProperty:valueType>
                            <pdfaProperty:category>external</pdfaProperty:category>
                            <pdfaProperty:description>The version of the Factur-X specification</pdfaProperty:description>
                          </rdf:li>
                          <rdf:li rdf:parseType="Resource">
                            <pdfaProperty:name>ConformanceLevel</pdfaProperty:name>
                            <pdfaProperty:valueType>Text</pdfaProperty:valueType>
                            <pdfaProperty:category>external</pdfaProperty:category>
                            <pdfaProperty:description>The conformance level of the embedded XML invoice</pdfaProperty:description>
                          </rdf:li>
                        </rdf:Seq>
                      </pdfaSchema:property>
                    </rdf:li>
                  </rdf:Bag>
                </pdfaExtension:schemas>
              </rdf:Description>
            </rdf:RDF>
          </x:xmpmeta>
          <?xpacket end="w"?>
        XMP
      end
      # rubocop:enable Metrics/MethodLength

      private_class_method def self.add_output_intent(doc)
        icc_path = File.join(DATA_DIR, "srgb.icc")
        icc_data = File.binread(icc_path)

        icc_stream = doc.add(
          { Type: :ICCBased, N: 3, Alternate: :DeviceRGB },
          stream: icc_data
        )
        icc_stream.set_filter(:FlateDecode)

        output_intent = doc.add({
          Type:                      :OutputIntent,
          S:                         :GTS_PDFA1,
          OutputConditionIdentifier: "sRGB IEC61966-2.1",
          Info:                      "sRGB IEC61966-2.1",
          DestOutputProfile:         icc_stream
        })

        doc.catalog[:OutputIntents] = [output_intent]
      end

      private_class_method def self.md5(bytes)
        require "digest"
        Digest::MD5.digest(bytes)
      end
    end
  end
end
