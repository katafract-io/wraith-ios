#!/usr/bin/env ruby
# Add Swift files that landed via PR merges but never made it into the
# Xcode project. Idempotent — re-running on a project that already has the
# files is a no-op.
#
# Usage: ruby scripts/add_missing_swift_files.rb

require 'xcodeproj'

PROJECT_PATH = 'WraithVPN.xcodeproj'
TARGET_NAME  = 'WraithVPN'

FILES = [
  { group: 'WraithVPN/App',      path: 'MockDataSeeder.swift' },
  { group: 'WraithVPN/Managers', path: 'DebugConformance.swift' },
  { group: 'WraithVPN/Views',    path: 'DebugConformanceView.swift' },
]

project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.find { |t| t.name == TARGET_NAME }
abort("target #{TARGET_NAME} not found") unless target

FILES.each do |f|
  group = project.main_group.find_subpath(f[:group], true)
  group.set_source_tree('<group>')
  ref = group.files.find { |x| x.path == f[:path] }
  ref ||= group.new_reference(f[:path])
  unless target.source_build_phase.files_references.include?(ref)
    target.source_build_phase.add_file_reference(ref, true)
    puts "added #{f[:group]}/#{f[:path]} to #{TARGET_NAME}"
  else
    puts "already present: #{f[:group]}/#{f[:path]}"
  end
end

project.save
puts "saved #{PROJECT_PATH}"
