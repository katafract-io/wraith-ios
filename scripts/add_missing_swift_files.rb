#!/usr/bin/env ruby
# Wire Swift files that landed via PR merges but never made it into the
# Xcode project. Idempotent — re-running is safe.
#
# This project flattens its source tree: files in WraithVPN/Foo/Bar.swift
# are added to the top-level "WraithVPN" group with a path of "Foo/Bar.swift"
# (sourceTree=<group>). Don't introduce intermediate PBXGroup nodes.
#
# Usage: ruby scripts/add_missing_swift_files.rb

require 'xcodeproj'

PROJECT_PATH = 'WraithVPN.xcodeproj'
TARGET_NAME  = 'WraithVPN'
PARENT_GROUP = 'WraithVPN'

# Each entry: relative path under WraithVPN/ (becomes the file ref's `path`).
SUBPATHS = [
  'App/MockDataSeeder.swift',
  'Managers/DebugConformance.swift',
  'Views/DebugConformanceView.swift',
]

project = Xcodeproj::Project.open(PROJECT_PATH)
target  = project.targets.find { |t| t.name == TARGET_NAME } || abort("target #{TARGET_NAME} not found")
parent  = project.main_group.find_subpath(PARENT_GROUP, false) || abort("group #{PARENT_GROUP} not found")
sources = target.source_build_phase

# 1. Drop any name-only intermediate groups a previous (buggy) run left behind.
%w[App Managers Views].each do |name|
  bad = parent.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.name == name && c.path.nil? }
  next unless bad
  bad.children.dup.each { |child| bad.remove_reference(child) }
  parent.remove_reference(bad)
  puts "removed shadow group #{name} (no path) under #{PARENT_GROUP}"
end

# 2. For each target subpath, drop any stray file refs whose path is just the
#    basename (broken — would resolve to WraithVPN/Foo.swift) along with their
#    Sources build files. Then ensure a single correct ref exists and is in
#    the Sources phase.
SUBPATHS.each do |sub|
  basename = File.basename(sub)

  # Remove broken refs (path == basename, no subdir).
  broken = project.files.select { |f| f.path == basename }
  broken.each do |bf|
    sources.files.dup.each do |bp|
      sources.remove_build_file(bp) if bp.file_ref == bf
    end
    bf.remove_from_project
    puts "removed broken file ref (path = #{basename})"
  end

  # Find or create the correct ref.
  ref = project.files.find { |f| f.path == sub }
  if ref.nil?
    ref = parent.new_reference(sub)
    puts "created file ref #{sub}"
  else
    puts "file ref already correct: #{sub}"
  end

  # Ensure exactly one Sources entry for this ref.
  ours = sources.files.select { |bp| bp.file_ref == ref }
  if ours.empty?
    sources.add_file_reference(ref, true)
    puts "added #{sub} to #{TARGET_NAME} Sources phase"
  elsif ours.size > 1
    ours[1..].each { |dup| sources.remove_build_file(dup) }
    puts "deduplicated Sources entries for #{sub} (kept 1, removed #{ours.size - 1})"
  end
end

project.save
puts "saved #{PROJECT_PATH}"
