# frozen_string_literal: true

module Einvoicing
  module Validators
    # Shared validation helpers for country-specific validators.
    # Each validator exposes a `.validate(invoice)` class method that returns
    # an array of error message strings (empty = valid).
    module Base
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Validate an invoice and raise if any errors exist.
        def validate!(invoice)
          errors = validate(invoice)
          raise ValidationError, errors.join("; ") unless errors.empty?

          true
        end
      end

      # Luhn algorithm for SIREN (9 digits) and SIRET (14 digits).
      # Returns true if the number passes the Luhn check.
      def self.luhn_valid?(number_string)
        digits = number_string.chars.map(&:to_i)
        sum = 0
        digits.reverse.each_with_index do |d, i|
          d = i.odd? ? d * 2 : d
          d -= 9 if d > 9
          sum += d
        end
        (sum % 10).zero?
      end

      # Basic presence check — returns an error string or nil.
      def self.presence(value, field_name)
        "#{field_name} is required" if value.nil? || value.to_s.strip.empty?
      end

      # Format check via regex — returns error string or nil.
      def self.format(value, field_name, pattern)
        "#{field_name} has invalid format" unless value.to_s.match?(pattern)
      end
    end

    # Raised when `.validate!` finds errors.
    class ValidationError < StandardError; end
  end
end
