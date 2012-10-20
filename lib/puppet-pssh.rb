#!/usr/bin/env ruby
require 'clamp'
require 'excon'
require 'json'
require 'logger'
require 'colored'

module PuppetPSSH

  VERSION = "0.1"

  if !defined? Log or Log.nil?
    Log = Logger.new($stdout)
    Log.formatter = proc do |severity, datetime, progname, msg|
      if severity == "INFO"
        "*".bold.cyan + " #{msg}\n"
      else
        severity = severity.red.bold if severity == 'ERROR'
        severity = severity.yellow.bold if severity == 'WARN'
        "#{Time.now.to_i} #{severity}: #{msg}\n"
      end
    end
    Log.level = Logger::INFO unless (ENV["DEBUG"].eql? "yes" or ENV["DEBUG"].eql? 'true')
    Log.debug "Initializing logger"
  end


  class BaseCommand < Clamp::Command
    
    option ["-m", "--match"], "REGEX", "Only the nodes matching the regex", :default => '.*'
    option ["-p", "--puppetmaster"], "PUPPETMASTER", "Puppet master host", :default => 'puppet'
    option "--puppetmaster-port", "PUPPETMASTER_PORT", "Puppet master port", :default => '8080'
    option "--use-ssl", :flag, "Use SSL (https) to communicate with the puppetmaster", :default => false
    option "--debug", :flag, "Print debugging output", :default => false do |o|
      Log.level = Logger::DEBUG 
    end

    def get_nodes(puppetmaster)
      url = "#{use_ssl? ? 'https' : 'http'}://#{puppetmaster}:#{puppetmaster_port}/nodes"
      Log.debug "Puppet master host: #{puppetmaster}"
      Log.debug "Puppet master url: #{url}"

      nodes = []
      begin
        out = Excon.get url
        JSON.parse(out.body).each do |n| 
          next unless  n =~ /#{match}/
          nodes << n 
        end
      rescue TypeError => e
        raise Exception.new "Error retrieving node list from master host: #{puppetmaster}"
      rescue Excon::Errors::SocketError => e
        raise Exception.new "Could not connect to the puppet master host: #{puppetmaster}"
      end
      nodes
    end

  end

  class List < BaseCommand 

    def execute
      begin
        get_nodes(puppetmaster).each { |n| puts n }
      rescue Exception => e
        Log.error e.message
        exit 1
      end
    end
  end

  # 
  # Run an arbitrary command using parallel-ssh against all the nodes
  # registered in the puppet master
  #
  # Needs pssh (parallel-ssh) installed.
  #
  class Run < BaseCommand 

    parameter "COMMAND ...", "Command to run"
    option "--nameserver", "DNS_SERVER", "Resolve node name using the given nameserver"
    option "--pssh-path", "PSSH_PATH", "Parallel-ssh command path", :default => '/usr/bin/parallel-ssh'
    option "--hostlist-path", "HOSTLIST_PATH", "Save host list to path", :default => '/tmp/puppet-pssh-run-hostlist'
    option ["-H", "--hostlist-path"], "HOSTLIST_PATH", "Save host list to path", :default => '/tmp/puppet-pssh-run-hostlist'
    option ["-o", "--node-output-path"], "NODE_OUTPUT_PATH", "Save host list to path", :default => '/tmp/'
    option "--[no-]host-key-verify", :flag, "Verify SSH host key", :default => true

    def execute
      unless File.exist?(pssh_path)
        Log.error "parallel-ssh command not found in #{pssh_path}."
        Log.error "Install it or use --pssh-path argument."
        exit 1
      end

      nodes = []
      begin
        nodes = get_nodes(puppetmaster)
      rescue => e
        Log.error e.message
        exit 1
      end

      unless File.exist?(hostlist_path)
        Log.info "Generating hostlist..."
        Log.debug "Hostlist path: #{hostlist_path}"
        # 
        # Optionally resolve names using specific DNS server
        #
        unless nameserver.nil?
          require 'net/dns'
          Log.info "DNS Server: #{nameserver}"
          Log.info "Resolving node names... (may take a while)"
          res = Net::DNS::Resolver.new
          res.nameservers = nameserver
        end
        #
        File.open hostlist_path, 'w' do |f|
          nodes.each do |i|
            address = i
            # try to resolve before writing the list
            Log.debug "Adding #{address}"
            unless nameserver.nil?
              address = res.query(i).answer.first.address rescue next
            end
            f.puts "#{address} root"
          end
        end
      else
        Log.warn "Using cached hostlist in #{hostlist_path}"
      end

      $stdout.sync = true
      command = "sleep `echo $[ ( $RANDOM % 30 )  + 1 ]`;" + command_list.join(' ')
      Log.info "Node log output path: #{node_output_path}"
      Log.info "Running command '#{command}' with parallel-ssh..."
      ssh_opts = ''
      unless host_key_verify?
        Log.warn 'Disabled host key verification'
        ssh_opts = '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
      end
      system "#{pssh_path} -p 40 -o #{node_output_path} -t 300 -h #{hostlist_path} -x '#{ssh_opts}' " + "'#{command} 2>&1'"
    end
  end

  class Driver < Clamp::Command

    subcommand "run", "Run an arbitrary command against the nodes", Run
    subcommand "list", "List registered nodes", List 

  end

end
