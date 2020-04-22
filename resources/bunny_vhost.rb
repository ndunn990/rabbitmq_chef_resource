# frozen_string_literal: true
#
# Cookbook Name:: igs_rabbitmq
# Resource:: bunny_vhost
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

resource_name :bunny_vhost

##############
# Properties #
##############
property :vhost, :kind_of => String, :name_attribute => true

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

def get_vhosts
  Chef::Log.debug("[bunny_vhost] Querying RabbitMQ for vhosts.")
  cmd = "rabbitmqctl list_vhosts --formatter json"
  cmd = get_shellout(cmd)
  cmd.run_command
  cmd.error!
  result = JSON.parse(cmd.stdout, object_class: OpenStruct)
  Chef::Log.debug("[bunny_vhost] rabbitmqctl list_vhosts : #{result}")
  return result
end

def vhost_exists?(vhost_name)
  current_vhosts = get_vhosts
  Chef::Log.debug("[bunny_vhost] Looking for #{vhost_name} in vhost list.")
  result = current_vhosts.select { |item| item['name'] == vhost_name}.first
  unless result.nil?
    Chef::Log.debug("[bunny_vhost] Found #{vhost_name} in vhost list.")
    return true
  else
    Chef::Log.debug("[bunny_vhost] Failed to find #{vhost_name} in vhost list.")
    return false
  end
end

###########
# Actions #
###########
action :add do
  rabbit_cmd = "/usr/sbin/rabbitmqctl"
  vhost = new_resource.vhost
  Chef::Log.info "-- Checking for vhost #{vhost} --"
  unless vhost_exists?(vhost)
    Chef::Log.info "-- Vhost #{vhost} does not exist. Creating it now. --"
    execute "run_rabbit - add vhost #{vhost}" do
      command "#{rabbit_cmd} add_vhost #{vhost}"
      environment shell_environment
      action :run
    end
  else
    Chef::Log.info "-- Vhost #{vhost} already exists. --"
  end
end
