#!/usr/bin/env ruby
# frozen_string_literal: true

# Builds the gem, installs the built package into a bundle that contains
# nothing else, and loads it.
#
# The development bundle is a liar: it carries every gem the tooling needs, so a
# `require` the gemspec forgot to declare resolves anyway and the suite stays
# green. A consumer gets a LoadError instead. This script reproduces the
# consumer's bundle.
#
# It works from the built package rather than the working directory on purpose.
# A `path:` source exposes the checkout as it is and never applies `s.files`, so
# it cannot see a file that the published gem leaves behind — an asset added
# under lib/ and read at runtime would ship broken with a green check.
#
# What it does NOT cover: a `require` that only runs at call time. base64 in
# einvoicing-connect and rexml here both sit inside method bodies and never fire
# during a load. spec/runtime_dependencies_spec.rb reads lib/ statically and
# covers those. Neither check replaces the other.
#
#   ruby script/check_isolated_load.rb [--project PATH]
#
# Exit status: 0 when the gem loads, 1 when it does not, 2 on a usage error.

require "fileutils"
require "tmpdir"

project = Dir.pwd
if (i = ARGV.index("--project"))
  project = ARGV[i + 1] or abort("--project needs a path")
end
project = File.expand_path(project)

gemspec_path = Dir[File.join(project, "*.gemspec")].first
abort("no gemspec in #{project}") unless gemspec_path

spec = Dir.chdir(project) { Gem::Specification.load(gemspec_path) }
abort("cannot load #{gemspec_path}") unless spec

# lib/<name>.rb is the entry point for both gems here (einvoicing.rb,
# einvoicing-connect.rb). Fall back to the nested form if that is the
# convention the gem follows instead.
entrypoint = [ spec.name, spec.name.tr("-", "/") ].find do |candidate|
  File.file?(File.join(project, "lib", "#{candidate}.rb"))
end
abort("no entry point found under #{project}/lib for gem #{spec.name}") unless entrypoint

exit_status = 1

Dir.mktmpdir("isolated-load") do |dir|
  package = File.join(dir, "#{spec.name}-#{spec.version}.gem")
  unpacked = File.join(dir, "unpacked")

  # Everything below runs with the project as cwd, never the temp directory: a
  # version manager picks the Ruby from the current directory, and the temp dir
  # carries no .ruby-version, so it would silently fall back to the global Ruby
  # while the gem paths still point at the project's.
  #
  # BUNDLE_PATH keeps the install inside the temp directory. Without it the
  # bundle lands in the caller's GEM_HOME and compiles native extensions there —
  # which is how a check that calls itself isolated ends up rebuilding openssl
  # against the wrong libruby on someone's workstation.
  env = {
    "BUNDLE_GEMFILE" => File.join(dir, "Gemfile"),
    "BUNDLE_PATH" => File.join(dir, "vendor"),
    # This bundle is generated here and has no lockfile of its own, so an
    # inherited BUNDLE_FROZEN — which CI sets for every other job — would make
    # the install refuse to start.
    "BUNDLE_FROZEN" => nil,
    "RUBYOPT" => nil
  }

  puts "building #{spec.name} #{spec.version}..."
  unless system("gem", "build", gemspec_path, "--output", package, "--quiet", chdir: project)
    warn "FAIL — gem build failed."
    next
  end

  # Unpack the package and give it back its gemspec, so Bundler can treat the
  # extracted tree — which holds exactly what s.files selected, nothing more —
  # as a path source.
  unless system("gem", "unpack", package, "--target", unpacked, chdir: project)
    warn "FAIL — gem unpack failed."
    next
  end

  root = File.join(unpacked, "#{spec.name}-#{spec.version}")
  spec_source = IO.popen([ "gem", "specification", package, "--ruby" ], &:read)
  unless $?.success?
    warn "FAIL — could not read the built package's gemspec."
    next
  end
  File.write(File.join(root, "#{spec.name}.gemspec"), spec_source)

  # Loading the gem does not prove its runtime assets shipped. Dropping
  # `Dir["config/locales/*.yml"]` from s.files leaves every require working and
  # every spec green — the locale specs read the checkout, not the package —
  # while I18n.load_path takes an empty glob and consumers get "translation
  # missing" everywhere. Extend this list when lib/ starts reading another
  # non-Ruby asset at runtime.
  runtime_assets = [ "config/locales/*.yml" ]
  missing_assets = runtime_assets.reject do |glob|
    Dir[File.join(project, glob)].empty? || Dir[File.join(root, glob)].any?
  end

  unless missing_assets.empty?
    warn <<~MSG
      FAIL — the built package is missing runtime assets: #{missing_assets.join(', ')}.

      The files exist in the checkout but s.files does not select them, so the
      published gem ships without them. Nothing else catches this: the code
      still loads, and the specs read the checkout rather than the package.
    MSG
    next
  end

  File.write(env["BUNDLE_GEMFILE"], <<~RUBY_GEMFILE)
    source "https://rubygems.org"
    gem #{spec.name.inspect}, path: #{root.inspect}
  RUBY_GEMFILE

  puts "installing it in a bundle holding nothing else..."
  unless system(env, "bundle", "install", "--quiet", chdir: project)
    warn "FAIL — bundle install failed. The gemspec asks for something that cannot resolve."
    next
  end

  # Load the entry point first — anything failing there fails the check. Then
  # every other file in the package, so a missing declaration hiding in a rarely
  # loaded file surfaces too.
  #
  # A NameError is tolerated only when the missing constant is a known host: a
  # gem legitimately ships files that cannot stand alone outside it —
  # einvoicing/rails/engine.rb subclasses ::Rails::Engine, which is why
  # lib/einvoicing.rb guards it with defined?(Rails::Engine).
  #
  # Any other NameError fails, because that is what an undeclared dependency
  # reached as a constant looks like: `CSV::DEFAULT_OPTIONS` without a require
  # raises "uninitialized constant CSV", and blanket-rescuing NameError would
  # wave it through — the static spec cannot see it either, since there is no
  # literal require to read. SyntaxError fails too: a file that does not parse
  # is not a file that was checked.
  script = <<~RUBY_SCRIPT
    require #{entrypoint.inspect}

    KNOWN_HOSTS = %i[Rails].freeze

    failures = []
    Dir[File.join(#{root.inspect}, "lib", "**", "*.rb")].sort.each do |file|
      begin
        require file
      rescue NameError => error
        next if error.instance_of?(NameError) && KNOWN_HOSTS.include?(error.name)

        failures << "\#{File.basename(file)}: \#{error.class}: \#{error.message}"
      rescue LoadError, StandardError, ScriptError => error
        failures << "\#{File.basename(file)}: \#{error.class}: \#{error.message}"
      end
    end

    unless failures.empty?
      warn "files in the package that do not load on their own:"
      failures.each { |line| warn "  \#{line}" }
      exit 1
    end

    puts "loaded #{spec.name} #{spec.version}"
  RUBY_SCRIPT

  if system(env, "bundle", "exec", "ruby", "-e", script, chdir: project)
    puts "OK — #{spec.name} loads from its built package with only its declared dependencies"
    exit_status = 0
  else
    warn <<~MSG
      FAIL — #{spec.name} does not load from its built package.

      Either something under lib/ requires a library the gemspec does not
      declare — it resolves in the development bundle because a development
      dependency drags it in — or a file the code needs is missing from the
      package because s.files does not select it.
    MSG
  end
end

exit exit_status
