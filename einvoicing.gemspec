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

  s.authors  = [ "Nathan Le Ray" ]
  s.email    = [ "nathan@sxnlabs.com" ]
  s.homepage = "https://www.sxnlabs.com/en/gems/einvoicing/"
  s.metadata = {
    "homepage_uri"      => "https://www.sxnlabs.com/en/gems/einvoicing/",
    "source_code_uri"   => "https://github.com/sxnlabs/einvoicing",
    "changelog_uri"     => "https://github.com/sxnlabs/einvoicing/blob/master/CHANGELOG.md",
    "documentation_uri" => "https://www.sxnlabs.com/en/gems/einvoicing/"
  }
  s.license  = "MIT"

  s.required_ruby_version = ">= 3.2"

  s.files = Dir["lib/**/*.rb", "lib/**/*.icc", "lib/**/*.xslt", "config/locales/*.yml",
                "README.md", "CHANGELOG.md", "LICENSE"]

  # Runtime dependencies.
  s.add_dependency "hexapdf", "~> 1.0"
  s.add_dependency "i18n",    "~> 1.0"

  # Dev/test dependencies.
  s.add_development_dependency "rspec",                "~> 3.13"
  s.add_development_dependency "rubocop",              "~> 1.70"
  s.add_development_dependency "rubocop-rails-omakase"
  s.add_development_dependency "rubocop-rspec",        "~> 3.0"
  s.add_development_dependency "nokogiri",             "~> 1.16" # XSD validation in specs
  s.add_development_dependency "rexml"    # Bundled gem in Ruby 4.0+
  s.add_development_dependency "prawn"    # PDF generation in sample scripts
  s.add_development_dependency "webmock", "~> 3.0"
end
