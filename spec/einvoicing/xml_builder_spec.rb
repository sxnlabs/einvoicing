# frozen_string_literal: true

require "spec_helper"

RSpec.describe Einvoicing::XMLBuilder do
  subject(:builder) { described_class.new }

  def xml
    builder.to_xml
  end

  describe "#tag with block" do
    it "emits opening and closing tags around content" do
      builder.tag("root") { builder.tag("child") { builder.text("leaf", "val") } }
      expect(xml).to include("<root>")
      expect(xml).to include("</root>")
      expect(xml).to include("<child>")
      expect(xml).to include("</child>")
    end

    it "skips emission entirely when block yields no content" do
      builder.tag("empty") { }
      expect(xml).not_to include("<empty")
    end

    it "emits a self-closing tag when called without a block" do
      builder.tag("solo")
      expect(xml).to include("<solo/>")
    end

    it "includes attributes on the opening tag" do
      builder.tag("item", "id" => "42") { builder.text("x", "y") }
      expect(xml).to include('<item id="42">')
    end

    it "escapes & in attribute values" do
      builder.tag("item", "name" => "a&b") { builder.text("x", "y") }
      expect(xml).to include('name="a&amp;b"')
    end

    it "escapes < in attribute values" do
      builder.tag("item", "val" => "a<b") { builder.text("x", "y") }
      expect(xml).to include('val="a&lt;b"')
    end

    it "escapes \" in attribute values" do
      builder.tag("item", "val" => 'say "hi"') { builder.text("x", "y") }
      expect(xml).to include("val=\"say &quot;hi&quot;\"")
    end
  end

  describe "#text escaping" do
    it "escapes & in text content" do
      builder.tag("root") { builder.text("el", "a&b") }
      expect(xml).to include("<el>a&amp;b</el>")
    end

    it "escapes < in text content" do
      builder.tag("root") { builder.text("el", "a<b") }
      expect(xml).to include("<el>a&lt;b</el>")
    end

    it "escapes > in text content" do
      builder.tag("root") { builder.text("el", "a>b") }
      expect(xml).to include("<el>a&gt;b</el>")
    end

    it 'escapes " in text content' do
      builder.tag("root") { builder.text("el", 'say "hi"') }
      expect(xml).to include("<el>say &quot;hi&quot;</el>")
    end

    it "escapes single quote in text content" do
      builder.tag("root") { builder.text("el", "it's") }
      expect(xml).to include("<el>it&apos;s</el>")
    end

    it "omits element when value is nil" do
      builder.tag("root") { builder.text("el", nil) }
      expect(xml).not_to include("<el")
    end
  end

  describe "indentation" do
    it "produces correct indentation for nested tags" do
      builder.tag("outer") do
        builder.tag("inner") do
          builder.text("leaf", "val")
        end
      end
      lines = xml.lines.map(&:chomp)
      outer_line = lines.find { |l| l.include?("<outer>") }
      inner_line = lines.find { |l| l.include?("<inner>") }
      leaf_line  = lines.find { |l| l.include?("<leaf>") }
      # depth 0 → no indent; depth 1 → 2 spaces; depth 2 → 4 spaces
      expect(outer_line).to start_with("<outer>")
      expect(inner_line).to start_with("  <inner>")
      expect(leaf_line).to start_with("    <leaf>")
    end
  end

  describe "XML declaration" do
    it "starts with XML declaration" do
      expect(xml).to start_with('<?xml version="1.0" encoding="UTF-8"?>')
    end
  end
end
