# encoding: utf-8
# vim: ft=ruby expandtab shiftwidth=2 tabstop=2

require 'shellwords'

service "iptables" do
  supports :status => true, :restart => true
  action [:disable, :stop]
end

wp_site_home = File.join(node[:devkit][:wp_docroot], node[:devkit][:wp_home])
wp_site_path = File.join(node[:devkit][:wp_docroot], node[:devkit][:wp_siteurl])
wp_site_url = File.join(node[:devkit][:wp_host], node[:devkit][:wp_siteurl])
# create site folder structure
directory wp_site_home do
    recursive true
    owner node[:devkit][:user]
    group node[:devkit][:group]
end

# download WordPress
if node[:devkit][:wp_version] =~ %r{^http(s)?://.*?\.zip$}
  code <<-EOH
    cd /tmp && wget -O ./download.zip #{Shellwords.shellescape(node[:devkit][:wp_version])} && unzip -d /var/www/ ./download.zip && rm ./download.zip
  EOH
elsif node[:devkit][:wp_version] == 'latest' then
  wp_cli_command 'core download' do
    user node[:devkit][:user]
    cwd wp_site_path
    args(
      :locale   => node[:devkit][:locale],
      :force    => ''
    )
  end
else
  wp_cli_command 'core download' do
    user node[:devkit][:user]
    cwd wp_site_path
    args(
      :locale   => node[:devkit][:locale],
      :version  => node[:devkit][:wp_version].to_s,
      :force    => ''
    )
  end
end

# WordPress config
file File.join(wp_site_path, "wp-config.php") do
  action :delete
  backup false
end

wp_cli_command 'core config' do
  user node[:devkit][:user]
  cwd wp_site_path
  args(
    :dbhost     => node[:devkit][:dbhost],
    :dbname     => node[:devkit][:dbname],
    :dbuser     => node[:devkit][:dbuser],
    :dbpass     => node[:devkit][:dbpassword],
    :dbprefix   => node[:devkit][:dbprefix],
    :locale     => node[:devkit][:locale],
    'extra-php' => "define('WP_HOME', 'http://#{File.join(node[:devkit][:wp_host], node[:devkit][:wp_home]).sub(/\/$/, '')}');\n"\
      "define('WP_SITEURL', 'http://#{wp_site_url.sub(/\/$/, '')}');\n"\
      "define('JETPACK_DEV_DEBUG', #{node[:devkit][:debug_mode]});\n"\
      "define('WP_DEBUG', #{node[:devkit][:debug_mode]});\n"\
      "define('FORCE_SSL_ADMIN', #{node[:devkit][:force_ssl_admin]});\n"\
      "define('SAVEQUERIES', #{node[:devkit][:savequeries]});"
  )
end

if node[:devkit][:always_reset] == true then
  # reset DB
  wp_cli_command 'db reset' do
    user node[:devkit][:user]
    cwd wp_site_path
    args(
      :yes    => ''
    )
  end
end

# WordPress install
wp_cli_command 'core install' do
  user node[:devkit][:user]
  cwd wp_site_path
  args(
    :url            => "http://#{wp_site_url}",
    :title          => node[:devkit][:title],
    :admin_user     => node[:devkit][:admin_user],
    :admin_password => node[:devkit][:admin_password],
    :admin_email    => node[:devkit][:admin_email]
  )
end

# default index page
unless node[:devkit][:wp_home] == node[:devkit][:wp_siteurl]
  wp_site_home_index = File.join(wp_site_home, 'index.php')
  unless File.exist?(wp_site_home_index)
    template wp_site_home_index do
      source "index.php.erb"
      owner node[:devkit][:user]
      group node[:devkit][:group]
      mode "0644"
      variables(
        :path => wp_site_path
      )
    end
  end
end

# install wp-multibyte-patch plugin if required by locale
if node[:devkit][:locale] == 'ja' then
  wp_cli_command 'plugin activate wp-multibyte-patch' do
    user node[:devkit][:user]
    cwd wp_site_path
  end
end

# install plugins
node[:devkit][:default_plugins].each do |plugin|
  wp_cli_command "plugin install #{Shellwords.shellescape(plugin)}" do
    user node[:devkit][:user]
    cwd wp_site_path
    args(
      :activate => ''
    )
  end
end

# install theme
if node[:devkit][:default_theme] != '' then
  wp_cli_command "theme install #{Shellwords.shellescape(node[:devkit][:default_theme])}" do
    user node[:devkit][:user]
    cwd wp_site_path
    args(
      :activate => ''
    )
  end
end

# theme unit testing
if node[:devkit][:theme_unit_test] == true then
  remote_file node[:devkit][:theme_unit_test_data] do
    source node[:devkit][:theme_unit_test_data_url]
    mode 0644
    action :create
  end

  wp_cli_command 'plugin install wordpress-importer' do
    user node[:devkit][:user]
    cwd wp_site_path
    args(
      :activate => ''
    )
  end

  wp_cli_command "import #{Shellwords.shellescape(node[:devkit][:theme_unit_test_data])}" do
    user node[:devkit][:user]
    cwd wp_site_path
    args(
      :authors => 'create'
    )
  end
end

# set options
node[:devkit][:options].each do |key, value|
  wp_cli_command "option update #{Shellwords.shellescape(key.to_s)} #{Shellwords.shellescape(value.to_s)}" do
    user node[:devkit][:user]
    cwd wp_site_path
  end
end

# rewrite structure
if node[:devkit][:rewrite_structure] then
  wp_cli_command "rewrite structure #{Shellwords.shellescape(node[:devkit][:rewrite_structure])}" do
    user node[:devkit][:user]
    cwd wp_site_path
  end

  wp_cli_command 'rewrite flush' do
    user node[:devkit][:user]
    cwd wp_site_path
    args(
      :hard  => ''
    )
  end
end

# multisite configuration
if node[:devkit][:is_multisite] == true then
  wp_cli_command 'core multisite-convert' do
    user node[:devkit][:user]
    cwd wp_site_path
  end

  # ~ [TODO] fix location
  template File.join(wp_site_home, 'nginx.conf') do
    source "multisite.nginx.conf.erb"
    owner node[:devkit][:user]
    group node[:devkit][:group]
    mode "0644"
  end
end

# create .gitignore file
template File.join(wp_site_home, '.gitignore') do
  source "gitignore.erb"
  owner node[:devkit][:user]
  group node[:devkit][:group]
  mode "0644"
  action :create_if_missing
  variables(
    :siteurl => File.join(node[:devkit][:wp_siteurl], '/')
  )
end

# ~%~ [TODO] 'port' to Nginx
# apache_site "000-default" do
#   enable false
# end

# web_app "wordpress" do
#   template "wordpress.conf.erb"
#   docroot node[:devkit][:wp_docroot]
#   server_name node[:fqdn]
# end
# ~%~

# Nginx configurartion
template File.join(node[:nginx][:dir], 'sites-available/default') do
  source "nginx.erb"
  owner "root"
  group "root"
  mode "0644"
  variables(
    :docroot => wp_site_path
  )
end

# ~%~ [TODO] port to Nginx
# bash "create-ssl-keys" do
#   user "root"
#   group "root"
#   cwd File.join(node[:nginx][:dir], 'ssl')
#   code <<-EOH
#     openssl genrsa -out server.key 2048
#     openssl req -new -key server.key -sha256 -subj '/C=JP/ST=Wakayama/L=Kushimoto/O=My Corporate/CN=#{node[:fqdn]}' -out server.csr
#     openssl x509 -in server.csr -days 365 -req -signkey server.key > server.crt
#   EOH
#   notifies :restart, "service[nginx]"
# end
# ~%~

template File.join(node[:devkit][:wp_docroot], ".editorconfig") do
  source "editorconfig.erb"
  owner node[:devkit][:user]
  group node[:devkit][:group]
  mode "0644"
  action :create_if_missing
end