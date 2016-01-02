#
# Cookbook Name:: ivanko
# Recipe:: default
#
# Copyright (C) 2015 Patrick Armitage
#
# All rights reserved - Do Not Redistribute
#

# Load the secrets file and the encrypted data bag item that holds the root password.
# password_secret = Chef::EncryptedDataBagItem.load_secret(node['awesome_customers']['passwords']['secret_path'])
# root_password_data_bag_item = Chef::EncryptedDataBagItem.load('passwords', 'sql_server_root_password', password_secret)
# Load the encrypted data bag item that holds the database user's password.
# user_password_data_bag_item = Chef::EncryptedDataBagItem.load('passwords', 'db_admin_password', password_secret)

include_recipe "ruby_rbenv::system"
include_recipe "ruby_build"
include_recipe "git"
include_recipe "sqlite"
include_recipe "nginx"

rbenv_ruby "2.2.4" do
  action :install
end
rbenv_global "2.2.4"

hostsfile_entry "10.33.33.33" do
  hostname  "rogue"
  action    :create_if_missing
end
hostsfile_entry "10.33.33.50" do
  hostname  "ivanko"
  action    :create_if_missing
end
hostsfile_entry "10.33.33.60" do
  hostname  "eleiko"
  action    :create_if_missing
end

group "admin" do
  gid 505
  action :create
end
user "deployer" do
  uid 505
  gid 505
  system true
  action :create
end

mysql2_chef_gem "default" do
  action :install
end
mysql_client "default" do
  action :create
end
mysql_service "default" do
  port "3306"
  version "5.5"
  initial_root_password "my_root_password"
  action [:create, :start]
end
mysql_database "workout" do
  connection(
    :host => "ivanko",
    :username => "root",
    :password => "my_root_password"
  )
  action :create
end

# Add a database user.
# mysql_database_user "deployer" do
#   connection(
#     :host => "127.0.0.1",
#     :username => "root",
#     :password => "my_root_password"
#   )
#   password "my_db_password"
#   database_name "workout"
#   host "127.0.0.1"
#   action [:create, :grant]
# end

directory "/var/local/ivanko/current" do
  owner "deployer"
  group "admin"
  mode 00755
  recursive true
end

git "/var/local/ivanko/current" do
  repository "https://github.com/patrick-armitage/backend.git"
  revision "HEAD"
  reference "master"
  action :sync
end

rbenv_gem "bundler"
execute "bundle install" do
  user "deployer"
  cwd "/var/local/ivanko/current"
end

application "/var/local/ivanko/current" do
  owner "deployer"
  group "admin"
  rails do
    database do
      database "workout"
      adapter "mysql2"
      username "root"
      host "localhost"
      password "my_root_password"
      socket "/var/run/mysql-default/mysqld.sock"
    end
  end
end

execute "rake db:migrate" do
  user "deployer"
  cwd "/var/local/ivanko/current"
end

secret = `cd /var/local/ivanko/current && rake secret`
template "/var/local/ivanko/current/config/secrets.yml" do
   source "rails_secrets.yml.erb"
   owner "deployer"
   group "admin"
   mode "0644"
   variables :secrets => { production: secret }
   action :create
end

rbenv_gem "puma"
puma_config "ivanko" do
  directory "/var/local/ivanko"
  environment "production"
  exec_prefix "rbenv exec"
  monit true
  logrotate false
  thread_min 0
  thread_max 16
  workers 1
end

template "/etc/nginx/sites-available/default" do
   source "nginx_default.erb"
   owner "deployer"
   group "admin"
   mode "0755"
   action :create
end

directory "/var/local/ivanko" do
  owner "deployer"
  group "admin"
  recursive true
  mode 00755
end

execute "sudo '/var/local/ivanko/shared/puma/puma_start.sh' &" do
  user "deployer"
end
