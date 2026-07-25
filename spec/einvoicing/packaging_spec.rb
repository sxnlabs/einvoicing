# frozen_string_literal: true

require "spec_helper"
require "rubygems"

RSpec.describe "the packaged gem", :aggregate_failures do # rubocop:disable RSpec/DescribeClass
  let(:root) { File.expand_path("../..", __dir__) }
  let(:gemspec) { Dir.chdir(root) { Gem::Specification.load("einvoicing.gemspec") } }

  # `gem build` copies each file's mode straight from the working tree, and git
  # records only the executable bit — so a 0600 file in a maintainer's checkout
  # ships as 0600 and the gem then fails to load for any non-root user, which is
  # every containerised app. Nothing in the diff would show it; this does.
  it "ships files every user can read" do
    unreadable = Dir.chdir(root) do
      gemspec.files.select { |file| File.exist?(file) && (File.stat(file).mode & 0o044).zero? }
    end

    expect(unreadable).to be_empty,
      "not readable by group or other: #{unreadable.join(", ")} — run `chmod go+r` on them"
  end

  it "ships no file the world can write" do
    writable = Dir.chdir(root) do
      gemspec.files.select { |file| File.exist?(file) && (File.stat(file).mode & 0o022).positive? }
    end

    expect(writable).to be_empty, "group- or world-writable: #{writable.join(", ")}"
  end

  it "lists only files that exist" do
    missing = Dir.chdir(root) { gemspec.files.reject { |file| File.exist?(file) } }

    expect(missing).to be_empty, "listed in the gemspec but absent: #{missing.join(", ")}"
  end
end
