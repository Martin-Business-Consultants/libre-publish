# frozen_string_literal: true

# A release a Docker install updated itself to (Upgrade::InPlace) carries the
# Ruby it was built with in ruby/, beside its gems. The image's own Ruby
# starts the process (the entrypoint and the binstubs belong to whatever
# image is deployed), so before anything else loads, start again on the
# release's Ruby. It wasn't built for this path, so point it at its own
# libruby (LD_LIBRARY_PATH), standard library (RUBYLIB, ahead of the built-in
# /usr/local paths) and binaries (PATH); its rbconfig.rb then works out every
# other path, RubyGems' among them, from its own place on disk.
#
# Plain Ruby, no gems: required first by config/boot.rb and bin/thrust. A
# checkout or an image has no ruby/ beside the app, so it does nothing there.
ruby_dir = File.expand_path("../ruby", __dir__)
bundled = File.join(ruby_dir, "bin", "ruby")

if File.executable?(bundled) && !ENV["CMS_BUNDLED_RUBY"] && File.realpath(RbConfig.ruby) != File.realpath(bundled)
  lib = File.join(ruby_dir, "lib", "ruby")
  version = Dir.children(lib).grep(/\A\d+\.\d+\.\d+\z/).max
  core = File.join(lib, version)
  arch = Dir.children(core).find { File.exist?(File.join(core, it, "rbconfig.rb")) }

  # The order Ruby searches its own: site, vendor, then the standard library.
  paths = %w[site_ruby vendor_ruby].flat_map { [File.join(lib, it, version), File.join(lib, it, version, arch), File.join(lib, it)] }
  paths += [core, File.join(core, arch)]

  join = ->(*parts) { parts.flatten.compact.reject(&:empty?).join(":") }
  ENV["CMS_BUNDLED_RUBY"] = bundled
  ENV["LD_LIBRARY_PATH"] = join.call(File.join(ruby_dir, "lib"), ENV["LD_LIBRARY_PATH"])
  # First on the PATH too, so what this process starts (Thruster's Puma, a
  # task running bin/rails) finds this Ruby through `#!/usr/bin/env ruby`,
  # not the image's with these settings.
  ENV["PATH"] = join.call(File.join(ruby_dir, "bin"), ENV["PATH"])
  ENV["RUBYLIB"] = join.call(paths.select { File.directory?(it) }, ENV["RUBYLIB"])
  exec bundled, $PROGRAM_NAME, *ARGV
end
