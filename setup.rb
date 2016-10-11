#!/usr/bin/env ruby

# =============================================================================
# Fabrica setup script
# =============================================================================
# IMPORTANT: before running this script, rename setup-example.yml to setup.yml
# and modify it with project info. see README.md for more info
# =============================================================================

require 'erb'
require 'fileutils'
require 'yaml'
require 'ostruct'

# copy starter source folder: this will preserve changes if/when kit updated
if not Dir.exists? 'dev/src'
	FileUtils.cp_r 'dev/src-starter', 'dev/src'
end

# load setup settings
puts '[Fabrica] Reading settings...'
begin
	# load default, user and project/site settings, in that order
	settings = YAML.load_file(File.join(File.dirname(__FILE__), 'provision/default.yml'))
	def settings.merge_settings!(settings_filename)
		if File.exists?(settings_filename)
			new_settings = YAML.load_file(settings_filename)
			self.merge!(new_settings) if new_settings.is_a?(Hash)
			return new_settings
		end
	end
	settings.merge_settings!(File.join(ENV['HOME'], '.fabrica/settings.yml'))
	setup_settings = settings.merge_settings!(File.join(File.dirname(__FILE__), 'setup.yml'))
	setup_settings['host_document_root'] = if setup_settings.has_key?('host_document_root') then setup_settings['host_document_root'] else settings['host_document_root'] end
rescue
	abort '[Fabrica] Could not load "setup.yml". Please create this file based on "setup-example.yml".'
end

# set configuration data in package.json, YWWProject.php and Wordmove files
settingsostruct = OpenStruct.new(settings)
def renderSourceFile(filename, settingsostruct, keeptemplate = nil)
	if File.exists?("#{filename}.erb")
		template = File.read "#{filename}.erb"
		file_data = ERB.new(template, nil, ">").result(settingsostruct.instance_eval { binding })
		File.open(filename, 'w') {|file| file.puts file_data }
		FileUtils.rm "#{filename}.erb" unless keeptemplate
	elsif not File.exists?("#{filename}")
		abort "[Fabrica] could not find #{filename}.erb template or #{filename}."
	end
end
renderSourceFile('dev/src/package.json', settingsostruct)
renderSourceFile('dev/src/includes/.env', settingsostruct)
renderSourceFile('dev/src/includes/composer.json', settingsostruct)
renderSourceFile('dev/src/includes/project.php', settingsostruct)
renderSourceFile('dev/src/templates/views/base.twig', settingsostruct)
renderSourceFile('Movefile', settingsostruct, true)

# rename/backup "setup.yml"
FileUtils.mv 'setup.yml', 'setup.bak.yml'
# create "vagrant.yml" file for Vagrant
setup_settings.reject! {|key| ['slug', 'title', 'author', 'homepage'].include?(key) }
File.open('vagrant.yml', 'w') {|file| file.write setup_settings.to_yaml }

# create symlinks to files kept in src folder but used in root by Fabrica
FileUtils.ln_s 'dev/src/fabrica-package.json', 'package.json'
FileUtils.ln_s 'dev/src/fabrica-gulpfile.js', 'gulpfile.js'

# install build dependencies (Gulp + extensions)
puts '[Fabrica] Installing build dependencies...'
system 'npm install'

# install initial front-end dependencies
puts '[Fabrica] Installing front-end dependencies...'
FileUtils.cd 'dev/src'
system 'npm install'
FileUtils.cd 'includes'
system 'composer install'
FileUtils.cd '../../..'

# start vagrant
puts '[Fabrica] Starting Vagrant VM...'
if not system 'vagrant up'
	abort '[Fabrica] Vagrant VM provisioning failed.'
end

# run our gulp build task and activate the theme in WordPress
puts '[Fabrica] Building theme and activating in WordPress...'
system 'gulp build'
# create symlink to theme folder in dev for quick access
FileUtils.ln_s "../#{settings['host_document_root']}/wp-content/themes/#{settings['slug']}/", 'dev/build'
system "vagrant ssh -c \"wp theme activate '#{settings['slug']}'\""

# after which, the site will be ready to run and develop locally
# just run gulp
puts '[Fabrica] Setup complete. To run and develop locally just run \'gulp\'.'
