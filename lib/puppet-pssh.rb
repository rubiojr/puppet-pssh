#!/usr/bin/env ruby
require 'clamp'
require 'excon'
require 'json'
require 'logger'
require 'colored'
require 'pp'

module PuppetPSSH

  VERSION = "0.2"

  if !defined? Log or Log.nil?
    Log = Logger.new($stdout)
    Log.formatter = proc do |severity, datetime, progname, msg|
      if severity == "INFO"
        "*".bold.cyan + " #{msg}\n"
      else
        severity = severity.red.bold if severity == 'ERROR'
        severity = severity.yellow.bold if severity == 'WARN'
        "*".bold.cyan + " #{severity}: #{msg}\n"
      end
    end
    Log.level = Logger::INFO unless (ENV["DEBUG"].eql? "yes" or ENV["DEBUG"].eql? 'true')
    Log.debug "Initializing logger"
  end


  class BaseCommand < Clamp::Command
    
    option ["-m", "--match"], "REGEX", "Only the nodes matching the regex", :default => '.*'
    option ["-p", "--puppetmaster"], "PUPPETMASTER", "Puppet master host", :default => 'puppet'
    option ["-P", "--puppetmaster-port"], "PUPPETMASTER_PORT", "Puppet master port", :default => '8080'
    option "--use-ssl", :flag, "Use SSL (https) to communicate with the puppetmaster", :default => false
    option "--debug", :flag, "Print debugging output", :default => false do |o|
      Log.level = Logger::DEBUG 
    end

    def master_url
      "#{use_ssl? ? 'https' : 'http'}://#{puppetmaster}:#{puppetmaster_port}/"
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

    option ["-a", "--all-facts"], :flag, "Print node facts", :default => false
    option ["-f", "--fact"], "FACT", "Print fact value"
    option "--with-facts", "FACTS", "Comman separated list of facts to look for"
    option "--status", :flag, "Print node status"

    def execute
      begin
        get_nodes(puppetmaster).each do |n| 
          next unless n =~ /#{match}/
          if all_facts?
            pp JSON.parse(Excon.get(master_url + "facts/#{n}").body)
          elsif fact
            value = JSON.parse(
              Excon.get(master_url + "facts/#{n}").body
            )['facts'][fact] || 'fact_not_found'
            puts n 
            puts "  #{fact.yellow}: " + value
          elsif with_facts
            facts = JSON.parse(
              Excon.get(master_url + "facts/#{n}").body
            )['facts']
            keys = facts.keys
            with_facts.split(',').each do |f|
              if keys.include?(f)
                puts n
                break
              end
            end
          elsif status?
            puts n
            status = JSON.parse(
              Excon.get(master_url + "status/nodes/#{n}").body
            )
            puts "  #{'name:'.ljust(20).yellow} #{status['name']}"
            puts "  #{'deactivated:'.ljust(20).yellow} " +
                 "#{status['deactivated'] || 'no'}"
            puts "  #{'catalog_timestamp:'.ljust(20).yellow} " + 
                 "#{status['catalog_timestamp']}"
            puts "  #{'facts_timestamp:'.ljust(20).yellow} " + 
                 "#{status['facts_timestamp']}"
          else
            puts n 
          end
        end
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
    option "--threads", "THREADS", "Use up to N threads", :default => 40
    option "--cached-hostlist", :flag, "Use cached hostlist", :default => false
    option ["-s","--splay"], :flag, "Wait a random piece of time", :default => false
    option ["-e","--extra-args"], "EXTRA_ARGS", "parallel-ssh extra arguments"
    option ["-l","--user"], "USER", "SSH user (parallel-ssh -l argument)", :default => 'root'

    def execute

      Log.info "SSH user: #{user}"
      Log.info "Node log output path: #{node_output_path}"
      Log.info "Max threads: #{threads}"

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

      # Delete previous hostlist unless specified otherwise
      unless cached_hostlist?
        File.delete hostlist_path if File.exist?(hostlist_path)
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
            f.puts "#{address}"
          end
        end
      else
        Log.warn "Using cached hostlist in #{hostlist_path}"
      end

      $stdout.sync = true
      if splay?
        Log.info "Using 30s splay"
        command = "sleep `echo $[ ( $RANDOM % 30 )  + 1 ]`;" + command_list.join(' ')
      else
        command = command_list.join(' ')
      end
      Log.info "Running command '#{command}' with parallel-ssh..."
      ssh_opts = ''
      extra_opts = "-l #{user} "
      if extra_args
        Log.info "Extra pssh arguments: #{extra_args}"
        extra_opts << extra_args
      end
      unless host_key_verify?
        Log.warn 'Disabled host key verification'
        ssh_opts = '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
      end
      full_cmd = "#{pssh_path} #{extra_opts} -p #{threads} -o #{node_output_path} -t 300 -h #{hostlist_path} -x '#{ssh_opts}' " + "'#{command} 2>&1'"
      Log.debug full_cmd
      system full_cmd
    end
  end

  class Driver < Clamp::Command

    subcommand "run", "Run an arbitrary command against the nodes", Run
    subcommand "list", "List registered nodes", List 

  end

end
