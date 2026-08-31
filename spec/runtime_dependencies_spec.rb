# frozen_string_literal: true

require "spec_helper"
require "ripper"

# A gem that `require`s a library it does not declare works fine in its own
# repository — the library is already there, dragged in by some development
# dependency — and fails in the consumer's bundle. Ruby 3.4 moved
# `bigdecimal` out of the default gems and Ruby 3.0 had already done the same to
# `rexml`. This gem required both from lib/ while declaring neither:
# `require "einvoicing"` died on bigdecimal, and rexml — required lazily inside
# parse_svrl — only blew up once Peppol validation ran. The 317-example suite
# stayed green throughout, because the development lock pulls both in
# transitively.
#
# This spec reads `lib/` instead of loading the gem in an isolated bundle,
# because it has to fail on a machine where the library IS installed. Loading
# the gem cannot do that either: the require that started all this sits inside
# a method body and never runs at load time.
RSpec.describe "runtime dependencies" do
  # Libraries that are still part of Ruby itself on every supported version.
  # Checked by loading each one inside a bundle whose lock contains none of
  # them, on the floor Ruby (3.2) and on the current release.
  #
  # A default gem can be demoted to a bundled gem in a later Ruby — that is what
  # happened to base64 in 3.4. When it does, the entry moves out of this list
  # and into the gemspec as a real dependency.
  let(:stdlib) { %w[date digest json net/http open3 tempfile uri] }

  let(:root) { File.expand_path("..", __dir__) }

  let(:gemspec) do
    Dir.chdir(root) { Gem::Specification.load("einvoicing.gemspec") }
  end

  let(:declared) do
    gemspec.dependencies.select { |dep| dep.type == :runtime }.map(&:name)
  end

  let(:required_libraries) do
    Dir[File.join(root, "lib/**/*.rb")].sort.flat_map do |file|
      # Read as UTF-8: the runner's locale may be US-ASCII, and an accented
      # comment would then blow up the lexer.
      required_literals(File.read(file, encoding: "UTF-8"))
    end.uniq.sort
  end

  # Guards the extractor itself. Every form here is ordinary Ruby that the first
  # version of this spec skipped, which would have shipped the very LoadError it
  # was written to prevent. The commented-out require must stay invisible.
  let(:awkward_requires) do
    <<~RUBY
      require("parenthesised")
      Kernel.require "with_receiver"
      require "first"; require "after_semicolon"
      def lazy
        require("inside_a_method") if condition?
      end
      # require "in_a_comment"
    RUBY
  end

  # Tokenising beats a regexp here. `require("x")`, `Kernel.require "x"` and a
  # require sitting after a semicolon are all ordinary Ruby that a
  # /^\s*require\s+"/ pattern silently skips — and a lazy `require("base64")`
  # inside a method is exactly the shape of the bug this spec exists to catch.
  # Ripper also refuses to see a `require` written in a comment or a string.
  def required_literals(source)
    tokens = Ripper.lex(source).map { |(_position, type, token, _state)| [ type, token ] }

    tokens.each_index.filter_map do |index|
      type, token = tokens[index]
      next unless type == :on_ident && token == "require"

      # Skip whitespace and an opening parenthesis to reach the argument.
      cursor = index + 1
      cursor += 1 while tokens[cursor] && %i[on_sp on_lparen].include?(tokens[cursor][0])

      # Only a literal string can be checked statically. `require SOME_CONST`
      # is invisible here, as it is to any static check.
      next unless tokens[cursor]&.first == :on_tstring_beg

      content = tokens[cursor + 1]
      content[1] if content&.first == :on_tstring_content
    end
  end

  # "bigdecimal/util" ships with the "bigdecimal" gem. Underscores and dashes
  # are dropped on both sides so that "active_support/core_ext" matches a
  # declared "activesupport" instead of demanding a gem name nobody publishes.
  def declared?(library, declared_names)
    first_segment = library.split("/").first
    normalized = first_segment.delete("_-")

    declared_names.any? { |name| name == first_segment || name.delete("_-") == normalized }
  end

  def internal?(library)
    File.file?(File.join(root, "lib", "#{library}.rb"))
  end

  it "declares every library lib/ requires that Ruby does not ship" do
    external = required_libraries.reject { |lib| stdlib.include?(lib) || internal?(lib) }
    undeclared = external.reject { |lib| declared?(lib, declared) }

    expect(undeclared).to be_empty, <<~MSG
      lib/ requires #{undeclared.join(', ')}, which the gemspec does not declare.

      This passes here and raises LoadError in a consumer's bundle. Add the gem
      to einvoicing.gemspec with add_dependency. If Ruby still ships it on every
      supported version, add it to `stdlib` in this spec and say why.
    MSG
  end

  it "keeps stdlib free of anything the gemspec already declares" do
    # A library in both lists means one of them is wrong, and the spec would
    # stop catching a missing declaration for it.
    overlap = stdlib.select { |lib| declared?(lib, declared) }

    expect(overlap).to be_empty
  end

  it "sees requires that a line-anchored regexp would miss" do
    expect(required_literals(awkward_requires)).to contain_exactly(
      "parenthesised", "with_receiver", "first", "after_semicolon", "inside_a_method"
    )
  end
end
