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

target = project.targets.find { |t| t.name == TARGET_NAME }
abort("target #{TARGET_NAME} not found") unless target

# 1. PBXFileReference for the xcframework, anchored under the WraithVPN/Frameworks group
group = project.main_group.find_subpath('WraithVPN/Frameworks', true)
group.set_source_tree('<group>')

existing = group.files.find { |f| f.path&.end_with?('Hysteria.xcframework') }
ref = existing || group.new_file('Hysteria.xcframework')
ref.set_source_tree('<group>')

# 2. Add to target's Frameworks build phase (link)
unless target.frameworks_build_phase.files_references.include?(ref)
  target.frameworks_build_phase.add_file_reference(ref, true)
end

# 3. Add to target's Embed Frameworks build phase (NE extensions still need it
#    embedded so the loader finds the dylib at runtime).
embed_phase = target.copy_files_build_phases.find { |p| p.symbol_dst_subfolder_spec == :frameworks }
embed_phase ||= target.new_copy_files_build_phase('Embed Frameworks').tap do |p|
  p.symbol_dst_subfolder_spec = :frameworks
end
unless embed_phase.files_references.include?(ref)
  build_file = embed_phase.add_file_reference(ref, true)
  build_file.settings ||= {}
  build_file.settings['ATTRIBUTES'] = ['CodeSignOnCopy', 'RemoveHeadersOnCopy']
end

# 4. FRAMEWORK_SEARCH_PATHS — make sure the xcframework folder is on the search path
target.build_configurations.each do |config|
  paths = config.build_settings['FRAMEWORK_SEARCH_PATHS'] || ['$(inherited)']
  paths = [paths] unless paths.is_a?(Array)
  marker = '$(PROJECT_DIR)/WraithVPN/Frameworks'
  paths << marker unless paths.include?(marker)
  config.build_settings['FRAMEWORK_SEARCH_PATHS'] = paths
end

# 5. Add HysteriaTransport.swift to the WireGuardTunnel target sources.
wgt_group = project.main_group.find_subpath('WireGuardTunnel', false)
hys_swift = wgt_group.files.find { |f| f.path == 'HysteriaTransport.swift' }
hys_swift ||= wgt_group.new_reference('HysteriaTransport.swift')
unless target.source_build_phase.files_references.include?(hys_swift)
  target.source_build_phase.add_file_reference(hys_swift, true)
end

project.save
puts "wired #{FRAMEWORK_PATH} + HysteriaTransport.swift into #{TARGET_NAME}"
