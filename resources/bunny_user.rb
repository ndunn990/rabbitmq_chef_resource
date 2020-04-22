# frozen_string_literal: true
#
# Cookbook Name:: rabbitmq
# Resource:: igs_rabbit_user
#
# Author: Nick Dunn <nickdunn@carrierpigeon.email>
# Copyright (C) 2020 Nick Dunn
# Original Inspiration: RabbitMQ Official Cookbook (https://github.com/rabbitmq/chef-cookbook)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
resource_name :bunny_user

################
# Dependencies #
################
include Chef::Mixin::ShellOut

##############
# Properties #
##############
property :user, :kind_of => String, :name_attribute => true
property :password, :kind_of => String
property :vhost, :kind_of => [String, Array]
property :conf_permission, :kind_of => String
property :write_permission, :kind_of => String
property :read_permission, :kind_of => String
property :tags, :kind_of => Array

##################
# Custom Methods #
##################
def shell_environment
  { 'HOME' => ENV.fetch('HOME', '/var/lib/rabbitmq') }
end

def get_shellout(cmd)
  sh_cmd = Mixlib::ShellOut.new(cmd, :env => shell_environment)
  sh_cmd
end

def get_users
  cmd = "rabbitmqctl list_users --formatter json"
  cmd = get_shellout(cmd)
  cmd.run_command
  cmd.error!
  result = JSON.parse(cmd.stdout, object_class: OpenStruct)
  Chef::Log.debug("[bunny_user] rabbitmqctl list_users : #{result}")
  return result
end

def find_user(username, current_user_list)
  result = current_user_list.select {|user| user['user'] == username}
  return result
end

def user_exists?(username, current_user_list)
  result = current_user_list.select {|user| user['user'] == username}
  Chef::Log.debug "User Check Result -> #{result}"
  unless result.empty?
    return true
  else
    return false
  end
end

def get_user_permissions(username)
  cmd = "rabbitmqctl list_user_permissions #{username} --formatter json"
  cmd = get_shellout(cmd)
  cmd.run_command
  cmd.error!
  result = JSON.parse(cmd.stdout, object_class: OpenStruct)
end

def get_vhosts
  Chef::Log.debug("[bunny_user] Querying RabbitMQ for vhosts.")
  cmd = "rabbitmqctl list_vhosts --formatter json"
  cmd = get_shellout(cmd)
  cmd.run_command
  cmd.error!
  result = JSON.parse(cmd.stdout, object_class: OpenStruct)
  Chef::Log.debug("[bunny_user] rabbitmqctl list_vhosts : #{result}")
  return result
end

def vhost_exists?(vhost_name)
  current_vhosts = get_vhosts
  Chef::Log.debug("[bunny_user] Looking for #{vhost_name} in vhost list.")
  result = current_vhosts.select { |item| item['name'] == vhost_name}.first
  unless result.nil?
    Chef::Log.debug("[bunny_user] Found #{vhost_name} in vhost list.")
    return true
  else
    Chef::Log.debug("[bunny_user] Failed to find #{vhost_name} in vhost list.")
    return false
  end
end

def permissions_exist?(vhost, user_permissions)
  Chef::Log.info "Checking to see if user's permissions exist for vhost #{vhost}"
  result = user_permissions.select { |perm| perm['vhost'] == vhost }.first
  unless result.nil?
    Chef::Log.info "Permissions exist for #{vhost}"
    return true
  else
    Chef::Log.info "Permissions do not exist for #{vhost}"
    return false
  end
end

def permissions_correct?(vhost, conf, write, read, user_permissions)
  Chef::Log.debug "Specified Permissions: Conf -> #{conf}, Write -> #{write}, Read -> #{read}"
  Chef::Log.debug "User permissions provided:  #{user_permissions}"
  relevant_perms = user_permissions.select { |perm| perm['vhost'] == vhost }.first
  Chef::Log.info "State of Current Permissionf for Vhost #{vhost} --> #{relevant_perms}"
  Chef::Log.info <<-STRING
  State of Current Permissions for Vhost #{vhost}:
  Conf -> #{relevant_perms['configure']}
  Write #{relevant_perms['write']}
  Read #{relevant_perms['read']}"
  STRING
  unless relevant_perms['configure'] == conf && relevant_perms['write'] == write && relevant_perms['read'] == read
    return false
  else
    return true
  end
end

def user_has_correct_tags?(user, tags)
  users = get_users
  current_user_object = users.select { |user_item| user_item['user'] == user }.first
  Chef::Log.info "User Object -> #{current_user_object}"
  #Chef::Log.info "I'm here."
  #Chef::Log.info "Tags -> #{current_user_object['tags']}"
  unless current_user_object.nil?
    unless current_user_object['tags'].empty?
      tags.each do |tag|
        unless current_user_object['tags'].include?(tag)
          # Since we have to set all tags at once, if even one is wrong, we should return false
          return false
        end
      end
    else
      Chef::Log.info "Current tag list is empty."
      return false
    end
  else
    Chef::Log.fatal "Something is wrong. Checked tags for #{user}, but user does not exist."
  end
  return true
end

###########
# Actions #
###########
action :add do
  rabbit_cmd = "/usr/sbin/rabbitmqctl"
  user = new_resource.user
  password = new_resource.password
  # Tags!
  unless new_resource.tags.nil?
    tags = new_resource.tags
  else
    # If nil, making sure it's at least an empty array
    tags = []
  end
  # Adding this tag by default so everyone knows Chef is managing internal users
  tags << 'managed-by-chef' unless tags.include?('managed-by-chef')
  Chef::Log.info "Current tag list -> #{tags}"
  current_user_list = get_users

  # Begin
  Chef::Log.info "-- Checking for user #{user} --"
  unless user_exists?(user, current_user_list)
    Chef::Log.info "-- Adding RabbitMQ user '#{user}' --"
    #add_user(user, password)
    execute "run_rabbit - add user #{user}" do
      command "#{rabbit_cmd} add_user #{user} #{password}"
      environment shell_environment
      action :run
    end
    Chef::Log.info <<-STRING
    Adding tags for new user #{user}
    #{tags}
    STRING
    tag_list = tags.join(" ")
    execute "run_rabbit - set tags for #{user}" do
      command "#{rabbit_cmd} set_user_tags #{user} #{tag_list}"
      environment shell_environment
      action :run
    end
  else
    Chef::Log.info "-- User #{user} already exists. Moving on. --"
    Chef::Log.info "-- Checking tags for #{user} --"
    Chef::Log.debug "(Will include the 'managed-by-chef' tag by default)"
    # Ensuring user's tags are up-to-date
    unless user_has_correct_tags?(user, tags)
      Chef::Log.info "User #{user} does not have the correct tag list."
      Chef::Log.info <<-STRING
      Adding tags for new user #{user}
      #{tags}
      STRING
      tag_list = tags.join(" ")
      execute "run_rabbit - set tags for #{user}" do
        command "#{rabbit_cmd} set_user_tags #{user} #{tag_list}"
        environment shell_environment
        action :run
      end
    else
      Chef::Log.info "User #{user} has the correct tag list. Moving on..."
    end
  end
end

action :set_permissions do
  rabbit_cmd = "/usr/sbin/rabbitmqctl"
  user = new_resource.user
  password = new_resource.password
  vhost = new_resource.vhost
  vhost = '/' if vhost.nil? || vhost.empty?
  conf_perm = new_resource.conf_permission
  write_perm = new_resource.write_permission
  read_perm = new_resource.read_permission
  current_user_list = get_users

  # Checking to see if user exists first.
  # If user exists, check to see if permissions exist for specified vhost, if they are correct, and update if needed.
  Chef::Log.info "-- Checking for user #{user} --"
  unless user_exists?(user, current_user_list)
      Chef::Log.fatal "Tried to set permissions for #{user}, but user #{user} does not exist; tried to create user, but the password property is nil!"
  else
    Chef::Log.info "-- Confirmed #{user} exists. Moving on. -- "
  end

  current_user_permissions = get_user_permissions(user)
  Chef::Log.info "-- Ensuring specified vhost (#{vhost}) actually exists --"
  unless vhost_exists?(vhost)
    Chef::Log.info "-- Vhost #{vhost} does not exist, so permissions will not be set. Moving on. --"
  else
    Chef::Log.info "-- Checking user #{user} permissions --"
    Chef::Log.debug "-- Ensuring permissions are not empty --"
    unless current_user_permissions.empty?
      Chef::Log.debug "-- Ensuring permissions exist for #{user} in vhost #{vhost} --"
      unless permissions_exist?(vhost, current_user_permissions)
        Chef::Log.info "-- Permissions do not exist for user #{user} in vhost #{vhost} -- "
        Chef::Log.info "-- Updating permissions for #{user} in vhost #{vhost} --"
        #run_rabbitmqctl("set_permissions --vhost '#{vhost}' '#{user}' '#{conf}' '#{write}' '#{read}'")
        execute "run_rabbit - set_permissions for #{user}" do
          command "#{rabbit_cmd} set_permissions --vhost '#{vhost}' '#{user}' '#{conf_perm}' '#{write_perm}' '#{read_perm}'"
          environment shell_environment
          action :run
        end
      else # Permissions for this vhost exist
        Chef::Log.debug "-- Permissions for user #{user} in vhost #{vhost} exist. --"
        Chef::Log.debug "-- Ensuring permissions are correct for #{user} in vhost #{vhost} --"
        unless permissions_correct?(vhost, conf_perm, write_perm, read_perm, current_user_permissions)
          Chef::Log.info "-- Permissions for #{user} in vhost #{vhost} are not correct --"
          Chef::Log.info "-- Updating permissions for #{user} in vhost #{vhost} --"
          #set_permissions(user, vhost, conf_perm, write_perm, read_perm)
          #run_rabbitmqctl("set_permissions --vhost '#{vhost}' '#{user}' '#{conf}' '#{write}' '#{read}'")
          execute "run_rabbit - set_permissions for #{user}" do
            command "#{rabbit_cmd} set_permissions --vhost '#{vhost}' '#{user}' '#{conf_perm}' '#{write_perm}' '#{read_perm}'"
            environment shell_environment
            action :run
          end
        else # Perms are correct
          Chef::Log.info "Permissions are correct for #{user} in vhost #{vhost}. Moving on..."
        end
      end
    else # Permissions are completely empty - there are none - so create some.
      Chef::Log.info "-- User #{user} has no permissions at all. --"
      Chef::Log.info "-- Updating permissions for #{user} in vhost #{vhost} --"
      #set_permissions(user, vhost, conf_perm, write_perm, read_perm)
      execute "run_rabbit - set_permissions for #{user}" do
        command "#{rabbit_cmd} set_permissions --vhost '#{vhost}' '#{user}' '#{conf_perm}' '#{write_perm}' '#{read_perm}'"
        environment shell_environment
        action :run
      end
    end
  end
end




