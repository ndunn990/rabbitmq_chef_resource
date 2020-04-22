# frozen_string_literal: true
#
# Cookbook Name:: igs_rabbitmq
# Resource:: reset_rabbitmq
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

resource_name :bunny_reset

##############
# Properties #
##############
property :reset_reason, :kind_of => String, :name_attribute => true

##################
# Custom Methods #
##################
def shell_environment
  { 'HOME' => ENV.fetch('HOME', '/var/lib/rabbitmq') }
end

###########
# Actions #
###########
action :reset do
  rabbit_cmd = "/usr/sbin/rabbitmqctl"
  # Execute rabbitmqctl command with args
  Chef::Log.warn("Resetting RabbitMQ due to #{new_resource.reset_reason}")
  service "rabbitmq-server" do
    action :restart
    notifies :run, 'execute[run_rabbit - stop_app (in order to reset RabbitMQ)]', :immediately
  end
  execute 'run_rabbit - stop_app (in order to reset RabbitMQ)' do
    command "#{rabbit_cmd} stop_app"
    environment shell_environment
    retries 3
    retry_delay 3
    notifies :run, 'execute[run_rabbit - RESET]', :immediately
  end
  execute "run_rabbit - RESET" do
    command "#{rabbit_cmd} stop_app"
    environment shell_environment
    action :nothing
    retries 3
    retry_delay 3
    notifies :run, 'execute[run_rabbit - start_app (in order to reset RabbitMQ)]', :immediately
  end
  execute "run_rabbit - start_app (in order to reset RabbitMQ)" do
    command "#{rabbit_cmd} start_app"
    environment shell_environment
    action :nothing
    retries 3
    retry_delay 3
  end
end

action :nothing do
  # Do nothing.
end
