#!/usr/bin/ruby 
#
#   Author: Rohith
#   Date: 2013-08-13 10:10:32 +0100 (Tue, 13 Aug 2013)
#  $LastChangedBy$
#  $LastChangedDate$
#  $Revision$
#  $URL$
#  $Id$
#
#  vim:ts=4:sw=4:et

$:.unshift File.join(File.dirname(__FILE__),'.','rubylibs')
require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'socket'
require 'pp'
require 'optparse'
require 'logging'
require 'nagiosutils'
require 'timeout'
begin
    require 'zookeeper'
rescue Exception => e
    puts "error: this plugin requires #{e.message}"
    exit 1
end

include Logging
include NagiosUtils

# Add any contributions / updates here
# date:    
# author: 
# desc:   
#

Meta = {
    :prog     => "#{__FILE__}",
    :author   => "Rohith",
    :email    => "gambol99@gmail.com",
    :date     => "2013-08-13 10:10:32 +0100",
    :version  => "0.0.2"
}

module Zookeeper

    class ZookeeperChecks

        include Logging
        include NagiosUtils

        attr_accessor :options

        def initialize( options )
            @options = options
            @verbose = options[:verbose]
        end

        def connect( hostname, port )
 
            instance = "#{hostname}:#{port}"
            begin
                verb( "attempting to connect to zookeeper instance on #{hostname}")
                Timeout::timeout( @options[:timeout] ) {
                    @zoo = TCPSocket::new hostname, port 
                }
            rescue Timeout::Error => e
                raise Timeout::Error, "timed out attempting to connect to zookeeper hostname "
            rescue Errno::ECONNREFUSED => e
                raise Errno::ECONNREFUSED, "connection refused to zookeeper instance"
            rescue Exception => e 
                raise "unable to connection to zooker hostname on #{hostname}, error: #{e.message}" 
            end
        end

        def get_zookeeper_stats( zookeeper, port, timeout, stats = {} )
            begin
                Timeout::timeout( timeout ) do 
                    verb( "connecting to zookeeper instance #{zookeeper}:#{port}" )
                    zoo = connect( zookeeper, port )
                    verb( "sending the mntr command to zookeeper instance" )
                    zoo.puts "mntr"
                    while line = zoo.gets
                        verb "received line: #{line}"
                        next unless line.match( /^zk_([a-zA-Z_]*)[ \s]+(.*)$/ )
                        key, value = $1, $2
                        stats[ key ] = value
                    end
                    verb( "retrieved monitoring statistics from zookeeper instance\n #{stats}" )
                end
            rescue Errno::ECONNREFUSED => e
                verb( "get_zookeeper_stats: connection refused to zookeeper: #{zookeeper}:#{port}" ) 
                raise Errno::ECONNREFUSED, "connection refused to zookeeper: #{zookeeper}:#{port}"
            rescue Timeout::Error => e
                verb( "get_zookeeper_stats: timed out trying to get statistics from #{zookeeper}:#{port}" )
                raise Timeout::Error, "timeout out attempting to connect to zookeeper instance #{zookeeper}:#{port}"
            rescue Exception => e 
                verb( "get_zookeeper_stats: threw an exception #{e.message}" )
                raise Exception, e.message
            end
            stats
        end

        def check_cluster
            begin

                verb "performing a cluster check on #{@options[:clusters]}"
                # step: lets get all the statistis and checks roles in the clusters
                zookeepers = []
                Timeout::timeout( @options[:timeout] ) do
                    @options[:cluster].each do |cluster|
                        instance, port = cluster[:instance],cluster[:port] 
                        verb( "check_cluster: getting the statistics from instance #{instance}:#{port}")
                        zoo = {}
                        begin
                            zoo[:success]  = false
                            zoo[:instance] = instance
                            zoo[:port]     = port 
                            zoo[:stats]    = get_zookeeper_stats( instance, port, 2 )
                            zoo[:success]  = true   
                        rescue Timeout::Error 
                            zoo[:error]    = "timeout"
                        rescue Exception   => e
                            zoo[:error]    = e.message
                        end
                        zookeepers << zoo 
                    end
                end

                @status      = :OK
                service_data = "Zookeeper Cluster:"
                perfdata     = ""
                
                verb( "received all the statistics from the zookeeper instances" )

                # check on the stability of the cluster for election, we need at the very least 3 boxes available
                available = zookeepers.select { |i| i[:success] == true }.size
                quit :CRITICAL, "unable to connect to any of the zookeeper instances" if available == 0
                if available < zookeepers.size
                    @status      = :WARNING
                    instances    = zookeepers.map { |i| "#{i[:instance]}:#{i[:port]}" if i[:success] == false }.delete_if{ |x| x == nil }.join(',')
                    service_data << ", unable to connect all the instances in cluster #{instances} seems down"
                end
                unless available % 2 > 0
                    @status       = :WARNING 
                    service_data  << ", election unstable, even number of instances"
                end 
                # lets check the current roles
                server_roles = zookeepers.map { |i| i[:stats]['server_state'] if i[:success] == true }.delete_if{ |x| x == nil }.inject(Hash.new(0)) do |h,k| 
                    h[k] = h[k] + 1
                    h
                end   

                # do we have a leader in the cluster?
                quit :CRITICAL, "" << service_data << ", the cluster have no leader, please check configuration"           unless server_roles.include?( 'leader' )
                unless !server_roles.include?( 'standalone')
                    instances = zookeepers.map { |i| "#{i[:instance]}:#{i[:port]}" if i[:stats]['server_state'] == 'standalone' }.join    
                    quit :CRITICAL, service_data << ", a standalone instance exists, cluster seems to be misconfigured, #{instances}" 
                end
                # we should have only three instance type
                instances = zookeepers.map { |i| "#{i[:instance]}:#{i[:port]}" unless ['standalone','leader', 'follower' ].include?( i[:stats]['server_state'] ) }.delete_if{ |x| x == nil }
                quit :CRITICAL, service_data << ", instances #{instances} have unknown server role" unless instances.empty?

                # we should check the znode count on each of the instances, as it's a indication of replication errors
                znode_count = zookeepers.map{ |i| i[:stats]['znode_count'] if i[:success] }.uniq.size
                unless znode_count == 1
                    @status = :WARNING if @status != :CRITICAL
                    service_data << ", the znode count is different across boxes, could indicate replication issues"
                end

                quit @status, "%s All Good" % [ service_data ]  

            rescue Timeout::Error => e
                verb( "check_cluster: timed out attempting to validate the cluster" )
                quit :CRITICAL, "unable to complete cluster check; timed out after #{@options[:timeout]} seconds"
            end

        end

        def check_instance( stats = {}, perf = {} )

            begin

                verb( "check_instance: performing validation of instance" )
                
                stats   = get_zookeeper_stats( @options[:hostname], @options[:port], @options[:timeout] )
                if @options[:metrics]
                    stats.each do |key,value|       
                        next unless value =~ /^[\d\.]*$/
                        now  = Time.now.to_i
                        puts "#{@options[:hostname]}.zookeeper.#{key} #{value} #{now}"
                    end
                    return
                end
                @status      = :OK
                perfdata     = ""
                stats.each do |key,value|
                    perf[key] = value if [ /^(.*_latency)$/,/^(packets_.*)/,/(.*descriptors)/, /(num_alive_connections)/, /(watch_count)/, /znode_count/ ].map { |x| key.match x }.compact.first
                end
                perfdata = perf.map { |k,v| "'#{k}'=#{v}" }.join(';; ')
                perfdata << ";;"

                # ok, lets do the actual checks now 
                status   = :OK
                quit :UNKNOWN, "unable to determine the role of the zookeeper"          unless stats['server_state']
                quit :WARNING, "statistics received does not contain average latency"   unless stats['avg_latency']
                quit :UNKNOWN, "unable to determine the version running"                unless stats['version']
                quit :UNKNOWN, "the version inforation looks invalid"                   unless stats['version'] =~ /^([0-9\.]+)/
                zookeeper_version = $1
                threshold( "Average Latency", stats["avg_latency"], @options[:warn_latency], @options[:crit_latency] )
                message  = "Zookeeper Running #{zookeeper_version}, role: #{stats['server_state']}" 
                quit @status, "#{message} | #{perfdata}"

            rescue Timeout::Error => e
                quit :CRITICAL, "timeout trying to check instance"
            end 
        end

    end


end

defaults = {
    :zookeeper_port     => 2181
}

options = { 
    :metric       => false,
    :port         => defaults[:zookeeper_port],
    :timeout      => 10,
    :warn_latency => 200,
    :crit_latency => 250 
}

Parser = OptionParser::new do |opts|
    opts.on( "-H", "--host hostname",      "the hostname | ip address of the zookeeper instance" )                            { |arg| options[:hostname]     = arg    }
    opts.on( "-p", "--port port",          "the port zookeeper is running on (defaults to #{defaults[:zookeeper_port]}")      { |arg| options[:port]         = arg    }
    opts.on( "-M", "--metrics",            "lets produce metric only on the instance" )                                       { options[:metrics]            = true   }
    opts.on( "-U", "--username username",  "the username to connect with to the node" )                                       { |arg| options[:username]     = arg    }
    opts.on( "-P", "--password password",  "the password to connect with to the node" )                                       { |arg| options[:password]     = arg    }
    opts.on( "-C", "--cluster cluster",    "a list of comma seperated zookeepers, we check replication, role and membership") { |arg| options[:cluster]      = arg    }
    opts.on( "-w", "--warn-latency ms",    "warn if the average latency is greater than x ms" )                               { |arg| options[:warn_latency] = arg    }
    opts.on( "-c", "--crit-latency ms",    "crticail if the average latency is greater than x ms" )                           { |arg| options[:crit_latency] = arg    }
    opts.on( "-v", "--verbose",            "switch on verbose logging" )                                                      { options[:verbose]            = true   }
end
Parser.parse!

# ok, lets validate the arguments
usage "you need to select either a hostname or cluster check"             if !options[:hostname] and !options[:cluster]
usage "you cannot check a hostname and a cluster at the same time"        if options[:hostname] and options[:cluster]

begin

    if options[:cluster]
        
        usage "a cluster by definition kinda needs more than one host" unless options[:cluster].split(',').size > 1
        clusters = []
        options[:cluster].split(',').each do |i|
            host = i
            port = 2181
            if i.split(':').size == 2
                spec = i.split(':')
                host, port = spec.first, spec.last
            end
            begin
                host = validate_hostname( host )
                port = validate_port( port )
            rescue ArgumentError => e
                usage "the specification for instance #{i} is invalid, please recheck"
            end
            clusters << { :instance => host, :port => port }
        end
        options[:cluster] = clusters
        # ok, we seem to have everything we need 

    else
        options[:hostname]     = validate_hostname( options[:hostname] ) 
        options[:port]         = validate_port( options[:port] ) 
        unless options[:metrics]
            options[:warn_latency] = validate_integer( options[:warn_latency], 10, 1000, "warn latency" )
            options[:crit_latency] = validate_integer( options[:crit_latency], 10, 1000, "crit latency" )
        end
    end     

rescue ArgumentError => e
    usage "#{e.message}"
end

# ok, we have everything we need to perform a check
begin 

    zoo = Zookeeper::ZookeeperChecks::new( options )
    # are we checking a individual instance or a cluster?
    if options[:cluster]
        verb( "checking zookeeper cluster: #{options[:cluster]} ")
        zoo.check_cluster
    else
        verb( "checkink zookeeper instance #{options[:hostname]}")
        zoo.check_instance
    end

rescue Errno::ECONNREFUSED => e
    quit :CRITICAL, "connection refused to zookeeper instance"
rescue SystemExit => e
    exit e.status
rescue Exception => e 
    puts "error: #{e.message} class: #{e.class}"
end




