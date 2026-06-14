#!/usr/bin/env ruby

require 'fileutils'
require 'pathname'
require 'xcodeproj'

ROOT = Pathname.new(__dir__).join('..').expand_path
PROJECT_PATH = ROOT.join('CodexQuotaDesktop.xcodeproj')

FileUtils.rm_rf(PROJECT_PATH)

project = Xcodeproj::Project.new(PROJECT_PATH.to_s)
project.root_object.attributes['LastUpgradeCheck'] = '1600'
development_team = 'G9K4MNXX8G'

app_group = project.main_group.new_group('App', 'App')
widget_group = project.main_group.new_group('Widget', 'Widget')
shared_group = project.main_group.new_group('Shared', 'Sources/CodexQuotaWidget')

app_target = project.new_target(:application, 'CodexQuotaDesktop', :osx, '14.0')
widget_target = project.new_target(:app_extension, 'CodexQuotaDesktopWidget', :osx, '14.0')

project.build_configurations.each do |config|
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '14.0'
  config.build_settings['SWIFT_VERSION'] = '6.0'
end

def configure_target(target, settings)
  target.build_configurations.each do |config|
    config.build_settings['SWIFT_VERSION'] = '6.0'
    config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '14.0'
    config.build_settings['INFOPLIST_FILE'] = settings[:info_plist]
    config.build_settings['CODE_SIGN_ENTITLEMENTS'] = settings[:entitlements]
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = settings[:bundle_id]
    config.build_settings['PRODUCT_NAME'] = settings[:product_name]
    config.build_settings['MARKETING_VERSION'] = '1.0'
    config.build_settings['CURRENT_PROJECT_VERSION'] = '1'
    config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
    config.build_settings['DEVELOPMENT_TEAM'] = development_team
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
    config.build_settings['CLANG_ENABLE_MODULES'] = 'YES'
    config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = [
      '$(inherited)',
      '@executable_path/../Frameworks',
      '@executable_path/../../Frameworks'
    ]
    settings.each do |key, value|
      next unless key.is_a?(String)
      config.build_settings[key] = value
    end
  end
end

configure_target(
  app_target,
  info_plist: 'App/Info.plist',
  entitlements: 'App/CodexQuotaDesktop.entitlements',
  bundle_id: 'com.ck.CodexQuotaDesktop',
  product_name: 'CodexQuotaDesktop',
  'SWIFT_EMIT_LOC_STRINGS' => 'NO'
)

configure_target(
  widget_target,
  info_plist: 'Widget/Info.plist',
  entitlements: 'Widget/CodexQuotaDesktopWidget.entitlements',
  bundle_id: 'com.ck.CodexQuotaDesktop.widget',
  product_name: 'CodexQuotaDesktopWidget',
  'APPLICATION_EXTENSION_API_ONLY' => 'YES',
  'SKIP_INSTALL' => 'YES',
  'SWIFT_EMIT_LOC_STRINGS' => 'NO'
)

shared_sources = %w[
  CodexQuotaModels.swift
  CodexQuotaSnapshotBuilder.swift
  CodexQuotaSupport.swift
  SQLiteSupport.swift
].map { |file| shared_group.new_file(file) }

app_sources = %w[
  CodexQuotaDesktopApp.swift
  ContentView.swift
  FileWatcher.swift
  QuotaDashboardViewModel.swift
].map { |file| app_group.new_file(file) }

widget_sources = %w[
  CodexQuotaWidget.swift
  CodexQuotaWidgetBundle.swift
].map { |file| widget_group.new_file(file) }

app_target.add_file_references(shared_sources + app_sources)
widget_target.add_file_references(shared_sources + widget_sources)

frameworks = {
  'SwiftUI.framework' => '/System/Library/Frameworks/SwiftUI.framework',
  'WidgetKit.framework' => '/System/Library/Frameworks/WidgetKit.framework',
  'AppKit.framework' => '/System/Library/Frameworks/AppKit.framework',
  'libsqlite3.tbd' => '/usr/lib/libsqlite3.tbd'
}

framework_refs = frameworks.transform_values do |path|
  project.frameworks_group.new_file(path)
end

[app_target, widget_target].each do |target|
  framework_refs.each_value do |ref|
    target.frameworks_build_phase.add_file_reference(ref, true)
  end
end

app_target.add_dependency(widget_target)
embed_phase = app_target.new_copy_files_build_phase('Embed App Extensions')
embed_phase.dst_subfolder_spec = '13'
embed_phase.add_file_reference(widget_target.product_reference)

project.save
