source "https://rubygems.org"

gemspec

# Development extras
group :development do
  gem "pry"
  gem "prawn"
  gem "prawn-table"
  gem "matrix"
  gem "webmock", "~> 3.0"

  # parallel 2.x requires Ruby >= 3.3, this gem supports >= 3.2 (gemspec + CI).
  # Pulled in transitively by rubocop.
  gem "parallel", "< 2.0"
end
