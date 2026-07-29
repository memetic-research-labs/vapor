#!/usr/bin/env ruby
# frozen_string_literal: true

# bump-version.rb
# Sets MARKETING_VERSION and CURRENT_PROJECT_VERSION on the Vapor app target.
#
# Usage:
#   ruby scripts/bump-version.rb <version> [build]
#
# The test targets carry their own unrelated version values, so this only
# touches build configurations belonging to the app bundle identifier.

APP_BUNDLE_ID = "lol.mrl.app.Vapor"
PBXPROJ = File.expand_path("../Vapor/Vapor.xcodeproj/project.pbxproj", __dir__)

def die(message)
  warn "ERROR: #{message}"
  exit 1
end

version = ARGV[0].to_s.strip
build = ARGV[1].to_s.strip
build = "1" if build.empty?

die "Usage: ruby scripts/bump-version.rb <version> [build]" if version.empty?
die "Version must look like X.Y.Z (got: #{version})" unless version.match?(/\A\d+\.\d+\.\d+\z/)
die "Build must be a positive integer (got: #{build})" unless build.match?(/\A\d+\z/)
die "Project not found at #{PBXPROJ}" unless File.file?(PBXPROJ)

original = File.read(PBXPROJ)

# Each build configuration is a "buildSettings = { ... };" block. Only the ones
# declaring the app bundle identifier belong to the Vapor app target.
block_pattern = /buildSettings = \{\n.*?\n\t\t\t\};/m

matched = 0
previous = []

updated = original.gsub(block_pattern) do |block|
  next block unless block.include?("PRODUCT_BUNDLE_IDENTIFIER = #{APP_BUNDLE_ID};")

  matched += 1
  previous << [
    block[/^\t+MARKETING_VERSION = (.+);$/, 1],
    block[/^\t+CURRENT_PROJECT_VERSION = (.+);$/, 1],
  ]

  block
    .sub(/^(\t+)MARKETING_VERSION = .+;$/) { "#{Regexp.last_match(1)}MARKETING_VERSION = #{version};" }
    .sub(/^(\t+)CURRENT_PROJECT_VERSION = .+;$/) { "#{Regexp.last_match(1)}CURRENT_PROJECT_VERSION = #{build};" }
end

# Debug and Release, and nothing else.
die "Expected 2 app build configurations, found #{matched}" unless matched == 2

previous.each do |marketing, current|
  die "A build configuration is missing MARKETING_VERSION" if marketing.nil?
  die "A build configuration is missing CURRENT_PROJECT_VERSION" if current.nil?
end

if updated == original
  puts "Already at #{version} (build #{build}); nothing to change."
  exit 0
end

File.write(PBXPROJ, updated)

# Read back to confirm the app target, and only the app target, moved.
verify = File.read(PBXPROJ)
app_versions = verify.scan(block_pattern).select { |b| b.include?("PRODUCT_BUNDLE_IDENTIFIER = #{APP_BUNDLE_ID};") }
                     .map { |b| [b[/^\t+MARKETING_VERSION = (.+);$/, 1], b[/^\t+CURRENT_PROJECT_VERSION = (.+);$/, 1]] }

unless app_versions.all? { |m, c| m == version && c == build }
  die "Verification failed; project.pbxproj may be inconsistent. Check `git diff`."
end

puts "Vapor app target: #{previous.first[0]} (build #{previous.first[1]}) -> #{version} (build #{build})"
puts ""
puts "Next:"
puts "  git commit -am \"chore: bump version to #{version}\""
puts "  APPLE_ID=... APPLE_APP_SPECIFIC_PASSWORD=... scripts/build-release.sh"
puts "  scripts/publish-release.sh dist/Vapor-#{version}-#{build}.dmg v#{version} --dry-run"
