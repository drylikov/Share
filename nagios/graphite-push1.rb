#!/usr/bin/ruby
#
#   Author: Rohith
#   Date: 2013-08-17 21:38:55 +0100 (Sat, 17 Aug 2013)
#
#  vim:ts=4:sw=4:et
#  
#  @TODO: need to be revisited, has a bug in here somewhere which causes the process to crash
#

$:.unshift File.join(File.dirname(__FILE__),'.','rubylibs')
require 'rubygems' if RUBY_VERSION < '1.9.0'
begin 
    require 'pp'
    require 'optparse'
    require 'logging'
    require 'nagiosutils'
    require 'timeout'
    require 'graphite-api'
rescue Exception => e 
    puts "[error] dependency error, required module missing: " << e.message
    exit 1
end

include NagiosUtils

options = {
    :port     => 2003,
    :spool    => '/var/nagios/spool/graphite',
    :log      => '/var/log/nagios/graphite-push.log',
    :interval => 10,
    :verbose  => false,
    :ignore   => [] 
}

module Nagios

    module Parser

        module PerformanceData

            def parse_perfdata( perf )
                #puts "parse_perfdata: perf=>#{perf}"
                metrics = perf.split( ' ' ).inject( {} ) do |m,item|
                    next unless item =~ /(.*)=([0-9\.]*)[;]?/
                    attribute  = $1.downcase
                    value      = $2
                    m[ attribute.gsub( / /, "_" ).gsub( /\//, 'slash_') ] = value if m and value
                    m
                end
                metrics
            end

            def log_invalid( line )
                log "invalid data: " << line
            end

            # parses each of the lines and yields { :hostname, :service, :values : epoch }
            def parse( file, &block )
                File.readlines( file ).each do |line|
                    unless line =~ /^DATATYPE::(HOSTPERFDATA|SERVICEPERFDATA)/
                        # we have a strange line in the file - just log it 
                        log_invalid( "no a datatype" << line )
                        next
                    end
                    # does the check have any performance data?
                    next if line =~ /(SERVICE|HOST)PERFDATA::[ \t]+/
                    metric = {}
                    line.split( "\t" ).each do |item|
                        log_invalid( "invalid column" << item ) unless item =~ /^([A-Za-z0-9]+)::(.*)$/
                        type, value = $1, $2
                        #puts "type=>#{type}"
                        case type
                        when /^TIMET$/
                            metric[:time]     = value
                        when /^HOSTNAME$/
                            metric[:hostname] = value.downcase
                        when /^HOSTCHECKCOMMAND$/
                            metric[:service]  = value.downcase
                        when /^SERVICEDESC$/
                            metric[:service]  = value.gsub( /[ \/]/,'_').downcase
                        when /^(SERVICE|HOST)PERFDATA$/
                            metrics           = parse_perfdata( value )
                            metric[:values]   = metrics if metrics
                        end
                        # we need to ignore certain things
                        ignore = false
                        @options[:ignore].each do |item|
                            ignore = true if metric[:service] =~ item
                        end    
                        log "ignore item %s" % [ metric[:service] ] if ignore
                        next if ignore
                    end
                    next unless metric[:values]   
                    yield metric if block_given? and metric.empty? == false
                end
            end

        end

    end

end

class GraphitePusher

    include Nagios::Parser::PerformanceData

    def initialize( options )
        @options   = options
        @verbose   = options[:verbose]
        @log       = nil
        @processed = 0
        begin 
            log "initialize: creating graphite connector to %s:%d" % [ @options[:hostname], @options[:port] ]
            graphite_host = "%s:%d" % [ @options[:hostname], @options[:port] ]
            @graphite = GraphiteAPI.new( :graphite => graphite_host, :interval => @options[:interval] )
            log "initialize: successfully initialized the graphite client"
        rescue Exception => e 
            log "initialize: unable to initialize graphite client: " << e.message 
            raise Exception, e.message
        end

    end

    def process
        begin
            while true
                files = get_performance_data
                unless files.empty?
                    log "process: found %d, (%s) files to process" % [ files.size, files.join(',') ]
                    files.each do |file|
                        log "process: processing file %s" % [ file ]
                        parse( file ) do |metric|
                            metrics = {}
                            metric[:values].each do |item,value|
                                met  = "%s.nagios.%s.%s" % [ metric[:hostname], metric[:service], item ]
                                metrics[met] = value
                            end
                            @graphite.metrics( metrics, Time.at( metric[:time].to_i ) )
                        end
                        log "process: processed file %s, deleting" % [ file ]
                        File.delete( file )
                    end
                end
                log "process: heading to sleep for " << @options[:interval].to_s << " seconds"
                sleep @options[:interval]
            end
        rescue Exception => e 
            log "process: threw exception: " << e.message
            raise Exception, e.message
        end
    end

    def get_performance_data( list = [] )
        begin
            list = Dir.glob( "#{@options[:spool]}/*perfdata*" )
            list
        rescue Exception => e 
            raise Exception, "get_performance_data: failed to get a listing of files, error: " << e.message
        end
    end

    def log( message = nil, logfile = @log ) 
        return unless message
        unless logfile
            @log    = File.open( @options[:log], "w+" )
            logfile = @log
        end
        msg = "%s : %s" % [ Time.now, message ] 
        logfile.puts "#{msg}\n" if logfile 
        logfile.flush if logfile
    end

end

Parser = OptionParser::new do |opts|
    opts.on( "-H", "--host hostname",       "the hostname / ip / vip of the graphite server" )             { |arg| options[:hostname]     = arg   }
    opts.on( "-p", "--port port",           "the port to push the statistics over" )                       { |arg| options[:port]         = arg   }
    opts.on( "-s", "--spool directory",     "the spool directory which holds the nagios perforamce data" ) { |arg| options[:spool]        = arg   }
    opts.on( "-i", "--interval seconds",    "the interval in second to poll the spool directory ")         { |arg| options[:interval]     = arg   }
    opts.on( "-l", "--log logfile",         "the file to push our logging to" )                            { |arg| options[:log]          = arg   }
    opts.on( "-v", "--verbose",             "switch on verbose logging" )                                  { options[:verbose]            = true  }
end
Parser.parse!

begin 

    options[:hostname] = validate_hostname( options[:hostname] )
    options[:port]     = validate_port( options[:port] )
    options[:spool]    = validate_directory( options[:spool] )
    options[:interval] = validate_integer( options[:interval], 1, 20, "interval" )

rescue ArgumentError => e
    usage e.message
rescue Exception => e 
    usage e.message
end

begin 
    pusher = GraphitePusher::new( options )
    pusher.process 
rescue Exception => e 
    puts "error: " << e.message
end

