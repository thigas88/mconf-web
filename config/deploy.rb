# This file is part of Mconf-Web, a web application that provides access
# to the Mconf webconferencing system. Copyright (C) 2010-2012 Mconf
#
# This file is licensed under the Affero General Public License version
# 3 or later. See the LICENSE file.

# Quick refs:
# (note: you can replace "staging" by "production" to set the target stage, see deploy/conf.yml)
#
#  cap staging setup:all                     # first time setup of a server
#  cap staging deploy:migrations             # update to a new release, run the migrations (i.e. updates the DB) and restart the web server
#  cap staging deploy:udpate                 # update to a new release
#  cap staging deploy:migrate                # run the migrations
#  cap staging deploy:restart                # restart the web server
#  cap staging rake:invoke TASK=jobs:queued  # run a rake task in the remote server
#
#  Other:
#  cap staging deploy:web:disable  # start maintenance mode (the site will be offline)
#  cap staging deploy:web:enable   # stop maintenance mode (the site will be online)
#  cap staging deploy:rollback     # go back to the previous version
#  cap staging setup:secret        # creates a new secret token (requires restart)
#  cap staging setup:db            # drops, creates and populates the db with the basic data
#

LOCAL_PATH = File.expand_path(File.dirname(__FILE__))

# RVM bootstrap
require "rvm/capistrano"
set :rvm_ruby_string, '1.9.3-p194@mconf'
set :rvm_type, :system

# bundler bootstrap
require 'bundler/capistrano'

# read the configuration file
CONFIG_FILE = File.join(File.dirname(__FILE__), 'deploy', 'conf.yml')
set :configs, YAML.load_file(CONFIG_FILE)

# multistage setup
set :stages, %w(production staging)
require 'capistrano/ext/multistage'

# anti-tty error
default_run_options[:pty] = true

# standard configuration for all stages
set :application, "mconf-web"
set :user, "mconf"
set :deploy_to, "/var/www/#{fetch(:application)}/"
set :deploy_via, :remote_cache
set :auto_accept, 0
set :keep_releases, 10

# whenever integration
set :whenever_command, "bundle exec whenever"
#set :whenever_environment, defer { stage }
require "whenever/capistrano"

# DEPLOY tasks
# They are used for each time the app is deployed
namespace :deploy do

  # Nginx tasks
  task(:start) {}
  task(:stop) {}
  task :restart, :roles => :app, :except => { :no_release => true } do
    run "#{try_sudo} touch #{File.join(current_path, 'tmp', 'restart.txt')}"
  end

  desc "Prints information about the selected stage"
  task :info do
    puts
    puts "*******************************************************"
    puts "        stage: #{ stage.upcase }"
    puts "       server: #{ fetch(:server) }"
    puts "       branch: #{ fetch(:branch) }"
    puts "   repository: #{ fetch(:repository) }"
    puts "  application: #{ fetch(:application) }"
    puts " release path: #{ release_path }"
    puts "*******************************************************"
    puts
  end

  # User uploaded files are stored in the shared folder
  task :symlinks do
    run "ln -sf #{shared_path}/public/logos #{release_path}/public"
    run "ln -sf #{shared_path}/attachments #{release_path}/attachments"
    # run "ln -sf #{shared_path}/public/scorm #{release_path}/public"
    # run "ln -sf #{shared_path}/public/pdf #{release_path}/public"
  end

  desc "Fix permissions in folders and files"
  task :fix_permissions, :roles => :app do
    run "#{try_sudo} chown -R #{user}:#{user_group} #{deploy_to}"
    run "#{try_sudo} chmod -R g+w #{shared_path}/attachments"
    run "#{try_sudo} chmod -R g+w #{shared_path}/public/logos"
  end

  desc "Send to the server the local configuration files"
  task :upload_config_files do
    top.upload "#{LOCAL_PATH}/database.yml", "#{release_path}/config/", :via => :scp
    top.upload "#{LOCAL_PATH}/setup_conf.yml", "#{release_path}/config/", :via => :scp
    top.upload "#{LOCAL_PATH}/analytics_conf.yml", "#{release_path}/config/", :via => :scp
  end

end

# SETUP tasks
# They are usually used only once when the application is being set up for the
# first time and affect the database or important setup files
namespace :setup do

  desc "Setup a server for the first time"
  task :all do
    top.deploy.setup      # basic setup of directories
    top.deploy.update     # clone git repo and make it the current release
    setup.db              # destroys and recreates the DB
    setup.secret          # new secret
    setup.statistics      # start google analytics statistics
    top.deploy.restart    # restart the server
  end

  desc "recreates the DB and populates it with the basic data"
  task :db do
    run "cd #{current_path} && bundle exec rake db:reset RAILS_ENV=production"
  end

  # User uploaded files are stored in the shared folder
  task :create_shared do
    run "#{try_sudo} mkdir -p #{shared_path}/attachments"
    run "#{try_sudo} mkdir -p #{shared_path}/public/logos"
  end

  desc "Creates a new secret in config/initializers/secret_token.rb"
  task :secret do
    run "cd #{current_path} && bundle exec rake secret:save RAILS_ENV=production"
    puts "You must restart the server to enable the new secret"
  end

  desc "Creates the Statistic table - needs config/analytics_conf.yml"
  task :statistics do
    run "cd #{current_path} && bundle exec rake statistics:init RAILS_ENV=production"
  end
end

namespace :rvm do
  desc 'Trust rvmrc file'
  task :trust_rvmrc do
    run "if [ -d #{current_release} ]; then rvm rvmrc trust #{current_release}; fi"
    run "if [ -d #{current_path} ]; then rvm rvmrc trust #{current_path}; fi"
  end
end

namespace :db do
  task :pull do
    run "cd #{current_release} && RAILS_ENV=production bundle exec rake db:data:dump"
    download "#{current_release}/db/data.yml", "db/data.yml"
    `bundle exec rake db:reset db:data:load`
  end
end

# From: http://stackoverflow.com/questions/312214/how-do-i-run-a-rake-task-from-capistrano
# example: cap staging invoke task=jobs:queued
desc "Run a task on a remote server."
task :invoke do
  run("cd #{deploy_to}/current; bundle exec rake #{ENV['TASK']} RAILS_ENV=production")
end

after 'multistage:ensure', 'deploy:info'
before 'deploy:setup', 'rvm:install_ruby'
after 'deploy:setup', 'setup:create_shared'
after 'deploy:setup', 'rvm:trust_rvmrc'
after 'deploy:setup', 'deploy:fix_permissions'
after 'deploy:update', 'deploy:cleanup'
after 'deploy:update_code', 'rvm:trust_rvmrc'
after 'deploy:update_code', 'deploy:symlinks'
after 'deploy:update_code', 'deploy:fix_permissions'
after 'deploy:finalize_update', 'deploy:upload_config_files'
