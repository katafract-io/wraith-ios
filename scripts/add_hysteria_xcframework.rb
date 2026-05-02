#!/usr/bin/env ruby
# Add Hysteria.xcframework to the WireGuardTunnel target.
#
# Wires the gomobile-bound Hysteria 2 client into the network extension so
# `import Hysteria` resolves. Run once after the xcframework is dropped into
# WraithVPN/Frameworks/. Idempotent — re-running on a project that already
# has the framework is a no-op.
#
# Usage: ruby scripts/add_hysteria_xcframework.rb

require 'xcodeproj'

PROJECT_PATH    = 'WraithVPN.xcodeproj'
FRAMEWORK_PATH  = 'WraithVPN/Frameworks/Hysteria.xcframework'
TARGET_NAME     = 'WireGuardTunnel'

project = Xcodeproj::Project.open(PROJECT_PATH)

ext_target = project.targets.find { |t| t.name == TARGET_NAME }
abort("extension target #{TARGET_NAME} not found") unless ext_target

# Find the main app target. App Store rule: frameworks must be embedded in the
# main .app bundle, not in the .appex. The extension target only LINKS the
# framework — embedding goes on the app target. Embedding inside the appex
# triggers altool 90205/90206: "disallowed nested bundles" / "disallowed file
# 'Frameworks'".
app_target = project.targets.find { |t| t.name == 'WraithVPN' }
abort("app target WraithVPN not found") unless app_target

# 1. PBXFileReference for the xcframework, anchored under the WraithVPN/Frameworks group
group = project.main_group.find_subpath('WraithVPN/Frameworks', true)
# Use a filesystem-path group (path = Frameworks), not a logical name-only
# group. Without path=, Xcode resolves children against the parent group's
# directory (WraithVPN/), so the xcframework path collapses to
# WraithVPN/Hysteria.xcframework and Archive errors with "no XCFramework
# found at WraithVPN/Hysteria.xcframework". With path=Frameworks the
# children resolve to WraithVPN/Frameworks/Hysteria.xcframework as written.
group.set_path('Frameworks')
group.set_source_tree('<group>')

existing = group.files.find { |f| f.path&.end_with?('Hysteria.xcframework') }
ref = existing || group.new_file('Hysteria.xcframework')
ref.set_source_tree('<group>')

# 2. EXTENSION target: link only (no embed — appex can't host its own
#    frameworks per App Store policy).
unless ext_target.frameworks_build_phase.files_references.include?(ref)
  ext_target.frameworks_build_phase.add_file_reference(ref, true)
end
# Strip any prior embed entry on the appex (left over from earlier scripts).
ext_target.copy_files_build_phases.each do |phase|
  next unless phase.symbol_dst_subfolder_spec == :frameworks
  phase.files.dup.each do |bf|
    if bf.file_ref == ref
      phase.remove_build_file(bf)
      puts "removed Embed Frameworks entry from #{TARGET_NAME} (appex can't embed)"
    end
  end
end

# 3. APP target: link AND embed. The extension picks up the framework at
#    runtime via the standard @rpath = "@executable_path/../../Frameworks"
#    that Xcode bakes into appex binaries that reference the main app's
#    frameworks dir.
unless app_target.frameworks_build_phase.files_references.include?(ref)
  app_target.frameworks_build_phase.add_file_reference(ref, true)
end
embed_phase = app_target.copy_files_build_phases.find { |p| p.symbol_dst_subfolder_spec == :frameworks }
embed_phase ||= app_target.new_copy_files_build_phase('Embed Frameworks').tap do |p|
  p.symbol_dst_subfolder_spec = :frameworks
end
unless embed_phase.files_references.include?(ref)
  build_file = embed_phase.add_file_reference(ref, true)
  build_file.settings ||= {}
  build_file.settings['ATTRIBUTES'] = ['CodeSignOnCopy', 'RemoveHeadersOnCopy']
end

# 4. FRAMEWORK_SEARCH_PATHS on BOTH targets — both link against the framework
#    at compile time, so both need the search path.
[ext_target, app_target].each do |t|
  t.build_configurations.each do |config|
    paths = config.build_settings['FRAMEWORK_SEARCH_PATHS'] || ['$(inherited)']
    paths = [paths] unless paths.is_a?(Array)
    marker = '$(PROJECT_DIR)/WraithVPN/Frameworks'
    paths << marker unless paths.include?(marker)
    config.build_settings['FRAMEWORK_SEARCH_PATHS'] = paths
  end
end

# 5. Add HysteriaTransport.swift to the WireGuardTunnel target sources.
wgt_group = project.main_group.find_subpath('WireGuardTunnel', false)
hys_swift = wgt_group.files.find { |f| f.path == 'HysteriaTransport.swift' }
hys_swift ||= wgt_group.new_reference('HysteriaTransport.swift')
unless ext_target.source_build_phase.files_references.include?(hys_swift)
  ext_target.source_build_phase.add_file_reference(hys_swift, true)
end

project.save
puts "wired #{FRAMEWORK_PATH}: linked into #{TARGET_NAME} (no embed), linked + embedded into WraithVPN app target; HysteriaTransport.swift in #{TARGET_NAME}"
