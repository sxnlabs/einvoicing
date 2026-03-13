# frozen_string_literal: true

module Einvoicing
  # Minimal zero-dependency XML builder used internally by format generators.
  # Produces indented XML with proper attribute and text escaping.
  class XMLBuilder
    def initialize
      @parts = ['<?xml version="1.0" encoding="UTF-8"?>']
      @depth = 0
    end

    # Build a non-empty element with an optional block for children.
    def tag(name, attrs = {}, &block)
      attr_str = serialize_attrs(attrs)
      if block
        @parts << "#{indent}<#{name}#{attr_str}>"
        @depth += 1
        yield
        @depth -= 1
        @parts << "#{indent}</#{name}>"
      else
        @parts << "#{indent}<#{name}#{attr_str}/>"
      end
    end

    # Build a text element: <Name>value</Name>.
    def text(name, value, attrs = {})
      return if value.nil?

      attr_str = serialize_attrs(attrs)
      @parts << "#{indent}<#{name}#{attr_str}>#{escape(value.to_s)}</#{name}>"
    end

    def to_xml
      @parts.join("\n")
    end

    private

    def indent
      "  " * @depth
    end

    def escape(str)
      str
        .gsub("&", "&amp;")
        .gsub("<", "&lt;")
        .gsub(">", "&gt;")
        .gsub('"', "&quot;")
    end

    def serialize_attrs(attrs)
      return "" if attrs.empty?

      attrs.map { |k, v| %( #{k}="#{escape(v.to_s)}") }.join
    end
  end
end
