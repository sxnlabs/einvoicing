# frozen_string_literal: true

require "spec_helper"
require "ripper"
require "yaml"

# i18n-tasks does not work on this gem: every lookup goes through
# `Einvoicing::I18n.t`, a wrapper that prefixes
# the key with `einvoicing.`, and its scanners only recognise a literal
# `I18n.t("full.key")`. It reported zero keys in use — which made `missing`
# falsely perfect and `unused` falsely total — while dragging railties and
# forty other gems into the lockfile. This spec replaces its `missing` side with
# no dependencies, by lexing the call sites the gem actually writes. It does not
# replace `unused`: keys are also built by interpolation here, so nothing can
# tell an orphan from a key only ever reached dynamically.
RSpec.describe "locales" do
  let(:root) { File.expand_path("..", __dir__) }
  let(:locale_files) { Dir[File.join(root, "config/locales/*.yml")].sort }

  let(:used_keys) do
    Dir[File.join(root, "lib/**/*.rb")].sort.flat_map do |file|
      translation_keys(File.read(file, encoding: "UTF-8"))
    end.uniq.sort
  end

  # Each file nests everything under its locale ("en:", "fr:"). That root is
  # stripped, otherwise every key would compare as different across locales.
  let(:locales) do
    locale_files.to_h do |file|
      data = YAML.safe_load_file(file)
      locale = data.keys.first
      [ locale, data.fetch(locale) ]
    end
  end

  # Every leaf, flattened to ["a.b.c", value], per locale.
  def leaves(node, prefix = [])
    return [ [ prefix.join("."), node ] ] unless node.is_a?(Hash)

    node.flat_map { |key, value| leaves(value, prefix + [ key.to_s ]) }
  end

  def leaf_keys(node)
    leaves(node).map(&:first)
  end

  # Literal keys handed to any `.t("...")` call. Interpolated keys such as
  # "errors.#{field}.missing" cannot be resolved statically and are skipped —
  # Ripper reports them as a different token sequence, so they never appear.
  def translation_keys(source)
    tokens = Ripper.lex(source).map { |(_position, type, token, _state)| [ type, token ] }

    tokens.each_index.filter_map do |index|
      next unless tokens[index] == [ :on_ident, "t" ]
      next unless tokens[index - 1]&.first == :on_period

      # Newlines are skipped too: wrapping a long `.t(` call over two lines is
      # the natural reflex, and stopping at the parenthesis would drop its key
      # from used_keys without a word.
      cursor = index + 1
      cursor += 1 while tokens[cursor] &&
                        %i[on_sp on_lparen on_nl on_ignored_nl].include?(tokens[cursor][0])
      next unless tokens[cursor]&.first == :on_tstring_beg

      content = tokens[cursor + 1]
      # A key built by interpolation lexes as embexpr, not as plain content.
      next unless content&.first == :on_tstring_content &&
                  tokens[cursor + 2]&.first == :on_tstring_end

      # `"errors." + role + ".missing"` would otherwise yield the fragment
      # "errors.", which resolves nowhere and turns a legitimate refactor red.
      after = cursor + 3
      after += 1 while tokens[after] && %i[on_sp on_nl on_ignored_nl].include?(tokens[after][0])
      next if tokens[after] == [ :on_op, "+" ]

      content[1]
    end
  end

  it "ships more than one locale" do
    # Without this the parity example below compares a locale against itself
    # and passes on anything: an entire locale file could vanish in a merge.
    expect(locales.size).to be >= 2
  end

  it "leaves no key without a translation" do
    empty = locales.flat_map do |locale, data|
      leaves(data).reject { |_key, value| value.is_a?(String) && !value.strip.empty? }
                  .map { |key, _value| "#{locale}.#{key}" }
    end

    expect(empty).to be_empty, <<~MSG
      These keys exist but carry no translation: #{empty.join(', ')}.
      The parity check sees them as present; I18n.t returns nothing useful.
    MSG
  end

  it "ships the same keys in every locale" do
    per_locale = locales.transform_values { |data| leaf_keys(data).sort }
    reference_locale, reference_keys = per_locale.first

    per_locale.each do |locale, keys|
      next if locale == reference_locale

      expect(keys).to eq(reference_keys), <<~MSG
        #{locale} and #{reference_locale} do not carry the same keys.
        Only in #{locale}: #{(keys - reference_keys).join(', ')}
        Only in #{reference_locale}: #{(reference_keys - keys).join(', ')}
      MSG
    end
  end

  it "resolves every literal key the code looks up" do
    known = locales.values.flat_map { |data| leaf_keys(data) }.uniq

    missing = used_keys.reject do |key|
      known.include?(key) || known.include?("einvoicing.#{key}")
    end

    expect(missing).to be_empty, <<~MSG
      lib/ looks up #{missing.join(', ')}, which no locale file defines.
      The call raises at runtime with a translation-missing string instead of
      the message it was written to show.
    MSG
  end

  it "finds the literal keys that lib/ looks up" do
    # Guards the extractor: an empty result would make the spec above pass on
    # anything at all.
    expect(used_keys).not_to be_empty
  end
end
