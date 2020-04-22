# frozen_string_literal: true
#
# Cookbook Name:: rabbitmq
# Resource:: igs_rabbitmq_policy
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

#actions :set, :clear, :list
#default_action :set

resource_name :bunny_policy

################
# Dependencies #
################
include Chef::Mixin::ShellOut

##############
# Properties #
##############
property :policy, :kind_of => String, :name_attribute => true
property :pattern, :kind_of => String
property :parameters, :kind_of => Hash
property :priority, :kind_of => Integer
property :vhost, :kind_of => String
property :apply_to, :kind_of => String, :equal_to => %w(all queues exchanges)

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

def get_policies(vhost)
  Chef::Log.debug("[bunny_policy] Querying RabbitMQ for policies for vhost #{vhost}.")
  cmd = "rabbitmqctl list_policies -p '#{vhost}' --formatter json"
  cmd = get_shellout(cmd)
  cmd.run_command
  cmd.error!
  result = JSON.parse(cmd.stdout, object_class: OpenStruct)
  return result
end

def policy_exists?(vhost, policy_name)
  policy_list = get_policies(vhost)
  unless policy_list.empty?
    Chef::Log.debug("[bunny_vhost] Checking if #{vhost} has current policy list")
    result = policy_list.select { |item| item['vhost'] == vhost}
    unless result.empty?
      Chef::Log.info("-- Located policy #{policy_name} for vhost #{vhost} --")
      return true
    else
      Chef::Log.info("-- Failed to locate current policy named #{policy_name} for vhost #{vhost}")
      return false
    end
  else
    Chef::Log.info("-- There are currently no policies found in RabbitMQ --")
    return false
  end
end

###########
# Actions #
###########
action :set do
  cmd = 'rabbitmqctl -q set_policy'
  cmd += " -p #{new_resource.vhost}" unless new_resource.vhost.nil?
  cmd += " --apply-to #{new_resource.apply_to}" if new_resource.apply_to
  cmd += " #{new_resource.policy}"
  cmd += " \"#{new_resource.pattern}\""
  cmd += " '{"

  first_param = true
  new_resource.parameters.each do |key, value|
    cmd += ',' unless first_param

    cmd += if value.is_a? String
             "\"#{key}\":\"#{value}\""
           else
             "\"#{key}\":#{value}"
           end
    first_param = false
  end

  cmd += "}'"
  cmd += " --priority #{new_resource.priority}" if new_resource.priority

  execute "set_policy #{new_resource.policy}" do
    command cmd
    environment shell_environment
  end

  Chef::Log.info "Done setting RabbitMQ policy '#{new_resource.policy}'."
end

action :clear do
  if policy_exists?(new_resource.vhost, new_resource.policy)
    cmd = "rabbitmqctl clear_policy #{new_resource.policy}"
    cmd += " -p #{new_resource.vhost}" unless new_resource.vhost.nil?
    execute "rabbitmq-clear_policy #{new_resource.policy}" do
      command cmd
      environment shell_environment
    end
    Chef::Log.info "Done clearing RabbitMQ policy '#{new_resource.policy}'."
  end
end

action :list do
  execute 'rabbitmq-list_policies' do
    cmd = 'rabbitmqctl list_parameters -q'
    command cmd
    environment shell_environment
  end
end
