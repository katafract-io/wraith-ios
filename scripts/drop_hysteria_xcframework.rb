#!/usr/bin/env ruby
# Remove Hysteria.xcframework wiring from the pbxproj.
#
# Background: builds 1505–1519 carried a gomobile-bound Hysteria.xcframework
# on top of WireGuardKitGo's libwg-go.a. Two Go runtimes in one appex →
# the extension crashed on launch and the tunnel never came up. The fix
# moves Hysteria into the same Go module as wireguard-go (hysbind.go in
# WireGuardKitGo), so libwg-go.a now contains both. The xcframework is no
# longer linked, no longer embedded, no longer referenced.
#
# This script is idempotent. Run once after pulling the unified-Go-module
# branch, then delete the xcframework dir from disk.
#
# Usage: ruby scripts/drop_hysteria_xcframework.rb

require 'xcodeproj'

PROJECT_PATH = 'WraithVPN.xcodeproj'

project = Xcodeproj::Project.open(PROJECT_PATH)

removed_build_files = 0
removed_phase_entries = 0
removed_search_path_entries = 0

# 1. Remove Hysteria.xcframework PBXFileReference + every PBXBuildFile that
#    points at it. xcodeproj's `remove_from_project` cascades to phases.
project.files.dup.each do |file_ref|
  next unless file_ref.path&.end_with?('Hysteria.xcframework')
  puts "removing file ref: #{file_ref.path}"
  file_ref.remove_from_project
  removed_build_files += 1
end

# 2. Remove HysteriaTransport.swift source ref (file deleted from disk).
project.files.dup.each do |file_ref|
  next unless file_ref.path == 'HysteriaTransport.swift'
  puts "removing source ref: HysteriaTransport.swift"
  file_ref.remove_from_project
end

# 3. Strip dangling Embed Frameworks phase entries that referenced Hysteria.
project.targets.each do |target|
  target.copy_files_build_phases.each do |phase|
    next unless phase.symbol_dst_subfolder_spec == :frameworks
    phase.files.dup.each do |bf|
      if bf.file_ref.nil? || bf.display_name&.include?('Hysteria.xcframework')
        phase.remove_build_file(bf)
        removed_phase_entries += 1
        puts "  scrubbed embed-frameworks entry on target #{target.name}"
      end
    end
  end
  target.frameworks_build_phase.files.dup.each do |bf|
    if bf.file_ref.nil? || bf.display_name&.include?('Hysteria.xcframework')
      target.frameworks_build_phase.remove_build_file(bf)
      removed_phase_entries += 1
      puts "  scrubbed link-frameworks entry on target #{target.name}"
    end
  end
end

# 4. Drop the FRAMEWORK_SEARCH_PATHS entry pointing at WraithVPN/Frameworks.
#    Xcode will still find system frameworks via $(inherited).
marker = '$(PROJECT_DIR)/WraithVPN/Frameworks'
project.targets.each do |target|
  target.build_configurations.each do |config|
    paths = config.build_settings['FRAMEWORK_SEARCH_PATHS']
    next unless paths.is_a?(Array) && paths.include?(marker)
    paths.delete(marker)
    config.build_settings['FRAMEWORK_SEARCH_PATHS'] = paths
    removed_search_path_entries += 1
    puts "  removed search path on #{target.name}/#{config.name}"
  end
end

# 5. Remove the now-empty WraithVPN/Frameworks group if it has no children.
group = project.main_group.find_subpath('WraithVPN/Frameworks', false)
if group && group.children.empty?
  puts "removing empty WraithVPN/Frameworks group"
  group.remove_from_project
end

project.save

puts "done — file refs:#{removed_build_files} phase entries:#{removed_phase_entries} search paths:#{removed_search_path_entries}"
