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
require 'fog'
require_relative 'linode_version'

module Kitchen

  module Driver
    # Linode driver for Kitchen.
    #
    # @author Brett Taylor <btaylor@linode.com>
    class Linode < Kitchen::Driver::Base
      kitchen_driver_api_version 2
      plugin_version Kitchen::Driver::LINODE_VERSION

      default_config :username, 'root'
      default_config :password, nil
      default_config :server_name, nil
      default_config :image, 140
      default_config :data_center, 4
      default_config :flavor, 1
      default_config :payment_terms, 1
      default_config :kernel, 138

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

      default_config :api_key, ENV['LINODE_API_KEY']

      required_config :api_key
      required_config :private_key_path
      required_config :public_key_path

      def create(state)
        # create and boot server
        config_server_name
        set_password

        if state[:linode_id]
          info "#{config[:server_name]} (#{state[:linode_id]}) already exists."
          return
        end

        info("Creating Linode - #{config[:server_name]}")

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
        Fog::Compute.new(:provider => 'Linode', :linode_api_key => config[:api_key])
      end

      def get_dc
        if config[:data_center].is_a? Integer
          data_center = compute.data_centers.find { |dc| dc.id == config[:data_center] }
        else
          data_center = compute.data_centers.find { |dc| dc.location =~ /#{config[:data_center]}/ }
        end

        if data_center.nil?
          fail(UserError, "No match for data_center: #{config[:data_center]}")
        end
        info "Got data center: #{data_center.location}..."
        return data_center
      end

      def get_flavor
        if config[:flavor].is_a? Integer
          if config[:flavor] < 1024
            flavor = compute.flavors.find { |f| f.id == config[:flavor] }
          else
            flavor = compute.flavors.find { |f| f.ram == config[:flavor] }
          end
        else
          flavor = compute.flavors.find { |f| f.name =~ /#{config[:flavor]}/ }
        end

        if flavor.nil?
          fail(UserError, "No match for flavor: #{config[:flavor]}")
        end
        info "Got flavor: #{flavor.name}..."
        return flavor
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
        data_center = get_dc
        flavor = get_flavor
        image = get_image
        kernel = get_kernel

        # submit new linode request
        compute.servers.create(
          :data_center => data_center,
          :flavor => flavor,
          :payment_terms => config[:payment_terms],
          :name => config[:server_name],
          :image => image,
          :kernel => kernel,
          :username => config[:username],
          :password => config[:password]
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
      def config_server_name
        if config[:server_name]
          config[:vm_hostname] = "#{config[:server_name]}"
          config[:server_name] = "kitchen-#{config[:server_name]}-#{instance.name}-#{Time.now.to_i.to_s}"
        else
          config[:vm_hostname] = "#{instance.name}"
          if ENV["JOB_NAME"]
            # use jenkins job name variable. "kitchen_root" turns into "workspace" which is uninformative.
            jobname = ENV["JOB_NAME"]
          elsif ENV["GITHUB_JOB"]
            jobname = ENV["GITHUB_JOB"]
          elsif config[:kitchen_root]
            jobname = File.basename(config[:kitchen_root])
          else
            jobname = 'job'
          end
          config[:server_name] = "kitchen-#{jobname}-#{instance.name}-#{Time.now.to_i.to_s}".tr(" /", "_")
        end

        # cut to fit Linode 32 character maximum
        if config[:server_name].is_a?(String) && config[:server_name].size >= 32
          config[:server_name] = "#{config[:server_name][0..29]}#{rand(10..99)}"
        end
      end

      # ensure a password is set
      def set_password
        if config[:password].nil?
          config[:password] = [*('a'..'z'),*('A'..'Z'),*('0'..'9')].sample(15).join
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
