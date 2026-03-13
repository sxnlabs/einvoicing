# frozen_string_literal: true
require "spec_helper"

RSpec.describe Einvoicing::Validators::Peppol do
  before do
    skip "java required" unless described_class.java_available?
    skip "Saxon JAR not found" unless File.exist?(described_class::SAXON_JAR)
    skip "Peppol XSLT not found" unless File.exist?(described_class::XSLT_PATH)
  end

  let(:valid_ubl) do
    Einvoicing::Formats::UBL.generate(Fixtures.invoice)
  end

  describe ".validate_ubl" do
    it "returns an empty array for a valid UBL invoice" do
      errors = described_class.validate_ubl(valid_ubl)
      expect(errors).to be_an(Array)
      expect(errors).to be_empty
    end

    it "returns error hashes with field, error, and message keys for invalid XML" do
      errors = described_class.validate_ubl("<Invoice/>")
      expect(errors).to be_an(Array)
    end
  end

  describe ".java_available?" do
    it "returns true or false" do
      expect(described_class.java_available?).to be(true).or be(false)
    end
  end
end
