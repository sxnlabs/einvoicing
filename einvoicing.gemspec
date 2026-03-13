require_relative "lib/einvoicing/version"

Gem::Specification.new do |s|
  s.name        = "einvoicing"
  s.version     = Einvoicing::VERSION
  s.summary     = "EU electronic invoicing for Ruby — EN 16931, Factur-X, UBL 2.1"
  s.description = <<~DESC
    EN 16931-compliant e-invoicing for Ruby. Generates Factur-X (PDF/A-3 + CII XML),
    UBL 2.1, and CII D16B. Validates French B2B requirements (SIREN, SIRET, TVA).
    Rails concern for ActiveRecord models. Targets French September 2026 mandate.
  DESC

  s.authors  = ["Nathan Le Ray"]
  s.email    = ["nathan@sxnlabs.com"]
  s.homepage = "https://github.com/sxnlabs/einvoicing"
  s.license  = "MIT"

  s.required_ruby_version = ">= 3.2"

  s.files = Dir["lib/**/*.rb", "README.md", "CHANGELOG.md", "LICENSE"]

  # Runtime dependency: PDF/A-3 embedding only.
  s.add_dependency "hexapdf", "~> 1.0"

  # Dev/test dependencies.
  s.add_development_dependency "rspec",   "~> 3.13"
  s.add_development_dependency "rubocop", "~> 1.65"
  s.add_development_dependency "nokogiri" # XSD validation in specs
  s.add_development_dependency "rexml"    # Bundled gem in Ruby 4.0+
  s.add_development_dependency "prawn"    # PDF generation in sample scripts
end
