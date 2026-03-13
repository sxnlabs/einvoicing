# frozen_string_literal: true

require "spec_helper"
require "hexapdf"

RSpec.describe Einvoicing::Formats::FacturX do
  # Generate a minimal valid PDF using HexaPDF directly.
  let(:minimal_pdf) do
    io = StringIO.new("".b)
    doc = HexaPDF::Document.new
    doc.pages.add
    doc.write(io)
    io.string
  end

  let(:xml_string) { "<Invoice><ID>TEST-001</ID></Invoice>" }

  describe ".embed" do
    it "raises ArgumentError when given non-PDF data (magic byte guard)" do
      expect {
        described_class.embed("not a pdf at all", xml_string)
      }.to raise_error(ArgumentError, /missing %PDF- magic bytes/)
    end

    it "returns a binary string starting with %PDF" do
      result = described_class.embed(minimal_pdf, xml_string)
      expect(result).to be_a(String)
      expect(result.b[0, 5]).to eq("%PDF-")
    end

    it "contains the string 'factur-x.xml' (filename embedded)" do
      result = described_class.embed(minimal_pdf, xml_string)
      expect(result).to include("factur-x.xml")
    end

    it "contains the XML content in the embedded file" do
      result = described_class.embed(minimal_pdf, xml_string)
      doc = HexaPDF::Document.new(io: StringIO.new(result))
      names_arr = doc.catalog[:Names][:EmbeddedFiles][:Names]
      # HexaPDF Names array layout: [name, filespec, name, filespec, ...]
      idx = nil
      names_arr.each_with_index { |v, i| idx = i if v == "factur-x.xml" }
      expect(idx).not_to be_nil
      filespec = names_arr[idx + 1]
      ef_stream = filespec[:EF][:F]
      content = ef_stream.stream
      expect(content.force_encoding("UTF-8")).to include("<Invoice>")
    end

    it "sets PDF/A-3 metadata (XMP contains pdfaid:part = 3)" do
      result = described_class.embed(minimal_pdf, xml_string)
      # XMP metadata is stored uncompressed per PDF/A-3 spec
      expect(result).to include("pdfaid:part")
      expect(result).to include("<pdfaid:part>3</pdfaid:part>")
    end
  end
end
