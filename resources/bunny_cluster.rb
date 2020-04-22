# frozen_string_literal: true
#
# Cookbook Name:: rabbitmq
# Provider:: cluster
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

resource_name :bunny_cluster

################
# Dependencies #
################
include Chef::Mixin::ShellOut

##############
# Properties #
##############
property :cluster_name,  :kind_of => String, :name_attribute => true # cluster name
property :cluster_nodes, :kind_of => Array                           # first node name to join

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

# Execute rabbitmqctl command with args
def run_rabbitmqctl(*args)
  cmd = "rabbitmqctl #{args.join(' ')}"
  Chef::Log.debug("[bunny_cluster] Executing #{cmd}")
  cmd = get_shellout(cmd)
  cmd.run_command
  begin
    cmd.error!
    Chef::Log.debug("[bunny_cluster] #{cmd.stdout}")
  rescue
    Chef::Application.fatal!("[bunny_cluster] #{cmd.stderr}")
  end
end

def get_cluster_status
  # execute > rabbitmqctl cluster_status"
  cmd = 'rabbitmqctl -q cluster_status --formatter json'
  Chef::Log.debug("[bunny_cluster] Executing #{cmd}")
  cmd = get_shellout(cmd)
  cmd.run_command
  cmd.error!
  result = JSON.parse(cmd.stdout, object_class: OpenStruct)
  Chef::Log.debug("[bunny_cluster] rabbitmqctl cluster_status : #{result}")
  result
end

def get_node_name
  # execute > rabbitmqctl eval 'node().'
  cmd = 'rabbitmqctl eval "node()." | head -1'
  Chef::Log.debug("[bunny_cluster] Executing #{cmd}")
  cmd = get_shellout(cmd)
  cmd.run_command
  cmd.error!
  result = cmd.stdout.chomp.delete("'")
  Chef::Log.debug("[bunny_cluster] node name : #{result}")
  result
end
def get_running_nodes(cluster_status_object)
  result = cluster_status_object['running_nodes']
  Chef::Log.debug("[bunny_cluster] running_nodes : #{result}")
  return result
end
def get_cluster_name(cluster_status_object)
  result = cluster_status_object['cluster_name']
  Chef::Log.debug("[bunny_cluster] cluster_name: #{result}")
  return result
end
def joined_cluster?(master_node, node_name, cluster_status_object)
  get_running_nodes(cluster_status_object).include?(node_name) && get_running_nodes(cluster_status_object).include?(master_node)
end

###########
# Actions #
###########
action :join do
  rabbit_cmd = "/usr/sbin/rabbitmqctl"
  Chef::Log.info "-- RabbitMQ CLI >>> #{rabbit_cmd} --"
  cluster_nodes = new_resource.cluster_nodes
  desired_cluster_name = new_resource.cluster_name

  # Master Node
  master_node = cluster_nodes.first
  cluster = get_cluster_status
  this_node = get_node_name

  if this_node == master_node
    # This node is the master node. Don't need to join it to itself, but should check cluster name.
    Chef::Log.info "This is the master node (BIG MOMMA); Cluster join will be skipped."
    Chef::Log.info "Since this is the master node, will ensure cluster name is correct..."
    current_cluster_name = get_cluster_name(cluster)
    unless current_cluster_name == desired_cluster_name
      execute "run_rabbit - set_cluster_name #{desired_cluster_name}" do
        command "#{rabbit_cmd} set_cluster_name #{desired_cluster_name}"
        environment shell_environment
        action :run
      end
      #new_cluster_status = get_cluster_status
      #new_cluster_name = get_cluster_name(new_cluster_status)
      Chef::Log.info(" -- Cluster name has been set : #{get_cluster_name(get_cluster_status)} -- ")
    else
      Chef::Log.info "Cluster name is correct. Moving on."
    end
  else
    unless joined_cluster?(master_node, this_node, cluster)
      # The following execute resources should run one after the other, but only when needed
      execute "run_rabbit - stop_app (for cluster join)" do
        command "#{rabbit_cmd} stop_app"
        environment shell_environment
        action :run
        retries 3
        retry_delay 3
        notifies :run, "execute[run_rabbit - join_cluster #{desired_cluster_name}]", :immediately
      end
      execute "run_rabbit - join_cluster #{desired_cluster_name}" do
        command "#{rabbit_cmd} join_cluster #{master_node}"
        environment shell_environment
        action :nothing
        retries 3
        retry_delay 3
        notifies :run, "execute[run_rabbit - start_app (for cluster join)]", :immediately
      end
      execute "run_rabbit - start_app (for cluster join)" do
        command "#{rabbit_cmd} start_app"
        environment shell_environment
        action :nothing
        retries 3
        retry_delay 3
      end
    else
      Chef::Log.info "[bunny_cluster] #{this_node} already joined to cluster #{desired_cluster_name}"
      Chef::Log.info "Moving on..."
    end
  end
end
