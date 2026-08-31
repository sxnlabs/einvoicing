#!/usr/bin/env ruby
# frozen_string_literal: true

# Verifies that every gem pinned in a Gemfile.lock can actually install on the
# lowest Ruby version the project claims to support.
#
# `bundle update` resolves against the Ruby you are running right now. On a
# machine running Ruby 4.0 it will happily pick a gem whose gemspec says
# `required_ruby_version >= 3.3`, producing a lockfile that cannot install in a
# CI job pinned to 3.2. Tests and RuboCop stay green locally; CI dies on
# `bundle install`.
#
#   ruby check_lock_ruby.rb --project PATH [--ruby X.Y.Z] [--json]
#
# Without --ruby the floor is inferred from, in order of precedence:
#   the gemspec's required_ruby_version, `ruby "..."` in the Gemfile,
#   .ruby-version, and every ruby-version: entry in .github/workflows/*.yml.
# The lowest of those wins — that is the Ruby the lockfile has to survive.
#
# Exit status: 0 when the lockfile installs on the floor, 1 when it does not,
# 2 on a usage or parsing error.

require "bundler"
require "json"
require "net/http"
require "optparse"
require "uri"

options = { project: Dir.pwd, json: false }
OptionParser.new do |o|
  o.banner = "usage: check_lock_ruby.rb --project PATH [--ruby X.Y.Z] [--json]"
  o.on("--project PATH", "Project directory (default: cwd)") { |v| options[:project] = v }
  o.on("--ruby VERSION", "Ruby floor to check against (default: inferred)") { |v| options[:ruby] = v }
  o.on("--json", "Machine-readable output") { options[:json] = true }
end.parse!

root = File.expand_path(options[:project])
lock_path = File.join(root, "Gemfile.lock")

abort("no Gemfile.lock in #{root}") unless File.file?(lock_path)

# LockfileParser resolves PATH sources relative to Bundler.root, which defaults
# to the cwd. Point it at the project or parsing blows up from anywhere else.
ENV["BUNDLE_GEMFILE"] = File.join(root, "Gemfile")

# --- Ruby floor -------------------------------------------------------------

# The project's locale may be US-ASCII; a gemspec with an accented author name
# would then blow up every regexp below.
def read_text(path)
  File.read(path, encoding: "UTF-8").scrub
end

def infer_floor(root)
  found = {}

  Dir[File.join(root, "*.gemspec")].each do |path|
    src = read_text(path)
    next unless (m = src.match(/required_ruby_version\s*=\s*(.*)$/))

    value = m[1]
    # An array value may be wrapped across lines: `required_ruby_version =
    # [">= 3.2",\n  "< 4.1"]`. Extend to the closing bracket, and no further —
    # swallowing the following lines would scoop up the add_dependency versions
    # underneath and drag the floor down to whichever is lowest.
    if value.count("[") > value.count("]")
      value += src[m.end(0)..].to_s[/\A.*?\]/m].to_s
    end

    # Only >= and ~> set a floor; an upper bound says nothing about the minimum.
    mins = value.scan(/[">']\s*(?:>=|~>)\s*(\d+\.\d+(?:\.\d+)?)/).flatten
    found[:gemspec] = mins.min_by { |v| Gem::Version.new(v) } if mins.any?
  end

  gemfile = File.join(root, "Gemfile")
  if File.file?(gemfile) && (m = read_text(gemfile).match(/^\s*ruby\s+["'](?:>=\s*)?(\d+\.\d+(?:\.\d+)?)/))
    found[:gemfile] = m[1]
  end

  rv = File.join(root, ".ruby-version")
  if File.file?(rv) && (m = read_text(rv).match(/(\d+\.\d+(?:\.\d+)?)/))
    found[:ruby_version_file] = m[1]
  end

  ci = Dir[File.join(root, ".github/workflows/*.yml")] + Dir[File.join(root, ".github/workflows/*.yaml")]
  ci_versions = ci.flat_map do |path|
    text = read_text(path)

    # `ruby-version: "3.2"` written straight into the step...
    direct = text.scan(/ruby[-_]version:\s*["']?(\d+\.\d+(?:\.\d+)?)/).flatten

    # ...and the matrix it usually reads from instead, where the step only says
    # `ruby-version: ${{ matrix.ruby }}` and the versions live in a list.
    matrix = text.scan(/^\s*ruby(?:[-_]version)?:\s*\[([^\]]+)\]/).flatten
                 .flat_map { |list| list.scan(/(\d+\.\d+(?:\.\d+)?)/).flatten }

    # ...or as a YAML block, where the versions are dashed items underneath.
    block = text.scan(/^\s*ruby(?:[-_]version)?:\s*\n((?:\s*-\s*["']?\d+\.\d+(?:\.\d+)?["']?\s*\n)+)/)
                .flatten
                .flat_map { |items| items.scan(/(\d+\.\d+(?:\.\d+)?)/).flatten }

    direct + matrix + block
  end
  found[:ci] = ci_versions.min_by { |v| Gem::Version.new(v) } if ci_versions.any?

  found
end

sources = infer_floor(root)
floor = options[:ruby] || sources.values.min_by { |v| Gem::Version.new(v) }

if floor.nil?
  warn "cannot infer a Ruby floor for #{root} (no gemspec, Gemfile ruby pin, .ruby-version or CI matrix)"
  warn "pass --ruby X.Y.Z explicitly"
  exit 2
end

# A floor of "3.2" means any 3.2.x, so compare against the highest patch of that
# series. Otherwise a gem requiring >= 3.2.1 would be wrongly flagged.
floor_version = Gem::Version.new(floor.count(".") == 1 ? "#{floor}.99" : floor)

# --- required_ruby_version per locked gem -----------------------------------

def remote_ruby_requirement(name, version)
  uri = URI("https://rubygems.org/api/v1/versions/#{name}.json")
  body = Net::HTTP.get_response(uri)
  return nil unless body.is_a?(Net::HTTPSuccess)

  entry = JSON.parse(body.body).find { |v| v["number"] == version.to_s }
  entry && entry["ruby_version"]
rescue StandardError
  nil
end

lock = Bundler::LockfileParser.new(read_text(lock_path))
offenders = []
unknown = []

lock.specs.each do |spec|
  # PATH/GIT sources are the project's own code, not something RubyGems installs.
  next if spec.source.is_a?(Bundler::Source::Path) || spec.source.is_a?(Bundler::Source::Git)

  requirement =
    begin
      Gem::Specification.find_by_name(spec.name, spec.version.to_s).required_ruby_version.to_s
    # Gem::MissingSpecError descends from LoadError, not StandardError.
    rescue StandardError, LoadError
      remote_ruby_requirement(spec.name, spec.version)
    end

  if requirement.nil?
    unknown << { name: spec.name, version: spec.version.to_s }
    next
  end

  next if requirement.strip.empty? || requirement == ">= 0"

  begin
    satisfied = Gem::Requirement.new(requirement.split(",").map(&:strip)).satisfied_by?(floor_version)
  rescue Gem::Requirement::BadRequirementError
    unknown << { name: spec.name, version: spec.version.to_s }
    next
  end

  offenders << { name: spec.name, version: spec.version.to_s, requires: requirement } unless satisfied
end

result = {
  project: root,
  ruby_floor: floor,
  floor_sources: sources,
  ok: offenders.empty?, # recomputed below once `unknown` is taken into account
  offenders: offenders,
  unknown: unknown
}

# An unverified gem is not a verified gem. Reporting OK while 74 of them could
# not be read — RubyGems rate-limiting the run, no network, specs not installed
# because the caller forgot `bundle exec` — turns this check into decoration.
ok = offenders.empty? && unknown.empty?
result[:ok] = ok

if options[:json]
  puts JSON.pretty_generate(result)
else
  puts "project    #{root}"
  puts "ruby floor #{floor} (#{sources.map { |k, v| "#{k}=#{v}" }.join(', ')})"
  if offenders.empty?
    puts "OK — every locked gem installs on Ruby #{floor}" if unknown.empty?
  else
    puts "FAIL — #{offenders.size} gem(s) cannot install on Ruby #{floor}:"
    offenders.each { |o| puts format("  %-28s %-12s requires ruby %s", o[:name], o[:version], o[:requires]) }
  end
  unless unknown.empty?
    puts "UNVERIFIED — #{unknown.size} gem(s) could not be read (spec not installed"
    puts "locally and RubyGems unreachable). Run under `bundle exec` so the specs"
    puts "resolve without the network, or retry when RubyGems answers."
    unknown.each { |u| puts "  #{u[:name]} #{u[:version]}" }
  end
end

exit(ok ? 0 : 1)
