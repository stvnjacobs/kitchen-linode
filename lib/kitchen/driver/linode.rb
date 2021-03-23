# -*- encoding: utf-8 -*-
#
# Author:: Brett Taylor (<btaylor@linode.com>)
#
# Copyright (C) 2015, Brett Taylor
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'kitchen'
require 'fog/linode'
require_relative 'linode_version'

module Kitchen

  module Driver
    # Linode driver for Kitchen.
    #
    # @author Brett Taylor <btaylor@linode.com>
    class Linode < Kitchen::Driver::Base
      kitchen_driver_api_version 2
      plugin_version Kitchen::Driver::LINODE_VERSION

      # used for connections
      default_config :username, 'root'
      default_config :password, nil
      # used for provisioning
      default_config :root_pass, nil
      default_config :label, nil
      default_config :image, 'linode/debian10'
      default_config :region, 'us-east'
      default_config :type, 'g6-standard-1'
      default_config :kernel, 'linode/grub2'

      default_config :sudo, true
      default_config :ssh_timeout, 600

      default_config :private_key_path do
        %w(id_rsa).map do |k|
          f = File.expand_path("~/.ssh/#{k}")
          f if File.exist?(f)
        end.compact.first
      end
      default_config :public_key_path do |driver|
        driver[:private_key_path] + '.pub' if driver[:private_key_path]
      end

      default_config :api_token, ENV['LINODE_TOKEN']

      required_config :api_token
      required_config :private_key_path
      required_config :public_key_path

      def create(state)
        # create and boot server
        config_label
        set_password

        if state[:linode_id]
          info "#{config[:label]} (#{state[:linode_id]}) already exists."
          return
        end

        info("Creating Linode - #{config[:label]}")

        server = create_server

        # assign the machine id for reference in other commands
        state[:linode_id] = server.id
        state[:hostname] = server.public_ip_address
        info("Linode <#{state[:linode_id]}> created.")
        info("Waiting for linode to boot...")
        server.wait_for { ready? }
        info("Linode <#{state[:linode_id]}, #{state[:hostname]}> ready.")
        setup_ssh(state) if bourne_shell?
      rescue Fog::Errors::Error, Excon::Errors::Error => ex
        raise ActionFailed, ex.message
      end

      def destroy(state)
        return if state[:linode_id].nil?
        server = compute.servers.get(state[:linode_id])

        server.destroy

        info("Linode <#{state[:linode_id]}> destroyed.")
        state.delete(:linode_id)
        state.delete(:pub_ip)
      end

      private

      def compute
        Fog::Compute.new(:provider => 'Linode', :linode_token => config[:api_token])
      end

      def get_dc
        if config[:region].is_a? Integer
          region = compute.regions.find { |dc| dc.id == config[:region] }
        else
          region = compute.regions.find { |dc| dc.location =~ /#{config[:region]}/ }
        end

        if region.nil?
          fail(UserError, "No match for region: #{config[:region]}")
        end
        info "Got data center: #{region.location}..."
        return region
      end

      def get_type
        if config[:type].is_a? Integer
          if config[:type] < 1024
            type = compute.types.find { |f| f.id == config[:type] }
          else
            type = compute.types.find { |f| f.ram == config[:type] }
          end
        else
          type = compute.types.find { |f| f.name =~ /#{config[:type]}/ }
        end

        if type.nil?
          fail(UserError, "No match for type: #{config[:type]}")
        end
        info "Got type: #{type.name}..."
        return type
      end

      def get_image
        if config[:image].is_a? Integer
          image = compute.images.find { |i| i.id == config[:image] }
        else
          image = compute.images.find { |i| i.name =~ /#{config[:image]}/ }
        end
        if image.nil?
          fail(UserError, "No match for image: #{config[:image]}")
        end
        info "Got image: #{image.name}..."
        return image
      end

      def get_kernel
        if config[:kernel].is_a? Integer
          kernel = compute.kernels.find { |k| k.id == config[:kernel] }
        else
          kernel = compute.kernels.find { |k| k.name =~ /#{config[:kernel]}/ }
        end
        if kernel.nil?
          fail(UserError, "No match for kernel: #{config[:kernel]}")
        end
        info "Got kernel: #{kernel.name}..."
        return kernel
      end

      def create_server
        region = get_region
        type = get_type
        image = get_image
        kernel = get_kernel

        # submit new linode request
        compute.servers.create(
          :region => region,
          :type => type,
          :label => config[:label],
          :image => image,
          :kernel => kernel,
          :root_pass => config[:root_pass]
        )
      end

      def setup_ssh(state)
        set_ssh_keys
        state[:ssh_key] = config[:private_key_path]
        do_ssh_setup(state, config)
      end

      def do_ssh_setup(state, config)
        info "Setting up SSH access for key <#{config[:public_key_path]}>"
        info "Connecting <#{config[:username]}@#{state[:hostname]}>..."
        ssh = Fog::SSH.new(state[:hostname],
                           config[:username],
                           :password => config[:password],
                           :timeout => config[:ssh_timeout])
        pub_key = open(config[:public_key_path]).read
        shortname = "#{config[:vm_hostname].split('.')[0]}"
        hostsfile = "127.0.0.1 #{config[:vm_hostname]} #{shortname} localhost\n::1 #{config[:vm_hostname]} #{shortname} localhost"
        @max_interval = 60
        @max_retries = 10
        @retries = 0
        begin
          ssh.run([
            %(echo "#{hostsfile}" > /etc/hosts),
            %(hostnamectl set-hostname #{config[:vm_hostname]}),
            %(mkdir .ssh),
            %(echo "#{pub_key}" >> ~/.ssh/authorized_keys),
            %(passwd -l #{config[:username]})
          ])
        rescue
          @retries ||= 0
          if @retries < @max_retries
            info "Retrying connection..."
            sleep [2**(@retries - 1), @max_interval].min
            @retries += 1
            retry
          else
            raise
          end
        end
        info "Done setting up SSH access."
      end

      # Set the proper server name in the config
      def config_label
        if config[:label]
          config[:label] = "kitchen-#{config[:label]}-#{instance.name}-#{Time.now.to_i.to_s}"
        else
          config[:label] = "#{instance.name}"
          if ENV["JOB_NAME"]
            # use jenkins job name variable. "kitchen_root" turns into "workspace" which is uninformative.
            jobname = ENV["JOB_NAME"]
          elsif ENV["TRAVIS_REPO_SLUG"]
            jobname = ENV["TRAVIS_REPO_SLUG"]
          else
            jobname = File.basename(config[:kitchen_root])
          end
          config[:label] = "kitchen-#{jobname}-#{instance.name}-#{Time.now.to_i.to_s}".tr(" /", "_")
        end

        # cut to fit Linode 32 character maximum
        if config[:label].is_a?(String) && config[:label].size >= 32
          config[:label] = "#{config[:label][0..29]}#{rand(10..99)}"
        end
      end

      # ensure a password is set
      def set_password
        if config[:root_pass].nil?
          config[:root_pass] = [*('a'..'z'),*('A'..'Z'),*('0'..'9')].sample(15).join
        end
      end

      # set ssh keys
      def set_ssh_keys
        if config[:private_key_path]
          config[:private_key_path] = File.expand_path(config[:private_key_path])
        end
        if config[:public_key_path]
          config[:public_key_path] = File.expand_path(config[:public_key_path])
        end
      end
    end
  end
end
