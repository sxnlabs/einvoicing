# frozen_string_literal: true

require "spec_helper"

# Plain Ruby class (no ActiveRecord) that includes the concern for testing.
class FakeInvoice
  include Einvoicing::Invoiceable

  attr_accessor :invoice_number, :issue_date, :due_date, :currency

  def initialize(invoice_number: "INV-2024-001", issue_date: Date.new(2024, 1, 15),
                 due_date: nil, currency: "EUR")
    @invoice_number = invoice_number
    @issue_date     = issue_date
    @due_date       = due_date
    @currency       = currency
  end

  def einvoicing_seller
    Fixtures.seller
  end

  def einvoicing_buyer
    Fixtures.buyer
  end

  def einvoicing_lines
    [ Fixtures.line ]
  end
end

RSpec.describe Einvoicing::Invoiceable do
  let(:fake_invoice) { FakeInvoice.new }

  describe "#einvoicing_valid?" do
    it "returns true for valid invoice data" do
      expect(fake_invoice.einvoicing_valid?).to be true
    end

    it "returns false when errors present (empty invoice number)" do
      invalid = FakeInvoice.new(invoice_number: "")
      expect(invalid.einvoicing_valid?).to be false
    end
  end

  describe "#einvoicing_errors" do
    it "returns empty array for valid invoice" do
      expect(fake_invoice.einvoicing_errors).to eq([])
    end

    it "returns array of hashes with :field, :error, :message keys" do
      invalid = FakeInvoice.new(invoice_number: "")
      errors  = invalid.einvoicing_errors
      expect(errors).to be_an(Array)
      expect(errors).not_to be_empty
      errors.each do |e|
        expect(e).to have_key(:field)
        expect(e).to have_key(:error)
        expect(e).to have_key(:message)
      end
    end
  end

  describe ".einvoicing_validator" do
    it "defaults to FR validator" do
      expect(FakeInvoice.einvoicing_validator).to eq(Einvoicing::Validators::FR)
    end

    it "can be overridden at class level" do
      custom_validator = Module.new do
        def self.validate(_invoice) = []
      end

      custom_class = Class.new do
        include Einvoicing::Invoiceable
        self.einvoicing_validator = custom_validator

        def invoice_number = "TEST-001"
        def issue_date     = Date.new(2024, 1, 1)
        def due_date       = nil
        def currency       = "EUR"
        def einvoicing_seller = Fixtures.seller
        def einvoicing_buyer  = Fixtures.buyer
        def einvoicing_lines  = [ Fixtures.line ]
      end

      instance = custom_class.new
      expect(custom_class.einvoicing_validator).to eq(custom_validator)
      expect(instance.einvoicing_valid?).to be true
    end
  end

  describe "#to_einvoice" do
    it "returns an Einvoicing::Invoice instance" do
      expect(fake_invoice.to_einvoice).to be_an(Einvoicing::Invoice)
    end

    it "maps invoice_number correctly" do
      expect(fake_invoice.to_einvoice.invoice_number).to eq("INV-2024-001")
    end

    it "maps seller correctly" do
      expect(fake_invoice.to_einvoice.seller).to eq(Fixtures.seller)
    end
  end
end
