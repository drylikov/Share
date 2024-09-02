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
begin
    gem "httparty"
rescue Gem::LoadError
     puts "Error, the plugin requires the httparty gem installed"
end
require 'httparty'
require 'pp'
require 'optparse'
require 'logging'
require 'nagiosutils'
require 'timeout'
require 'rexml/document'

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
    :date     => "2013-08-14 12:12:32 +0100",
    :version  => "0.0.1"
}

options = { 
    :hostname     => 'localhost',
    :port         => 8161,
    :timeout      => 10,
    :verbose      => false,
    :warning      => nil,
    :critical     => nil,
    :metrics      => false,
    :secure       => false
}
# lets get the options
Parser = OptionParser::new do |opts|
    opts.on( "-H", "--host hostname",      "the hostname | ip address of the activemq instance" )                   { |arg| options[:hostname]     = arg    }
    opts.on( "-p", "--port port",          "the port activemq is running on (defaults to #{options[:port]})")       { |arg| options[:port]         = arg    }
    opts.on( "-t", "--timeout timeout",    "the critical threshold of queue count" )                                { |arg| options[:timeout]      = arg    }
    opts.on( "-U", "--username username",  "the username to connect with to the node" )                             { |arg| options[:username]     = arg    }
    opts.on( "-P", "--password password",  "the password to connect with to the node" )                             { |arg| options[:password]     = arg    }
    opts.on( "-Q", "--queue name",         "the name of queue you wish to check, defaults to all" )                 { |arg| options[:queue]        = arg    }
    opts.on( "-S", "--secure",             "use https rather than http for activemq api call" )                     { |arg| options[:secure]       = true   }
    opts.on( "-w", "--warning  warning",   "the warning threshold of queue count" )                                 { |arg| options[:warning]      = arg    }
    opts.on( "-c", "--critical critical",  "the critical threshold of queue count" )                                { |arg| options[:critical]     = arg    }
    opts.on( "-M", "--metrics",            "produce metrics only on the queues, no thresholding" )                  { |arg| options[:metrics]      = true   }
    opts.on( "-v", "--verbose",            "switch on verbose logging" )                                            { |arg| options[:verbose]      = true   }
end
Parser.parse!

username = nil
password = nil
queue    = nil

# lets validate the arguments
begin
    
    @verbose = options[:verbose] if options[:verbose]
    hostname = validate_hostname( options[:hostname] )
    port     = validate_port( options[:port] )
    timeout  = validate_timeout( options[:timeout], 5, 60 )
    username = validate_username( options[:username] ) if options[:username] 
    password = validate_password( options[:password] ) if options[:password]
    queues   = validate_string( options[:queue], /^.*$/, "queue" ) if options[:queue]
    warning  = validate_threshold( options[:warning],  "the queue count warning threshold is invalid"  ) unless options[:metrics]
    critical = validate_threshold( options[:critical], "the queue count critical threshold is invalid" ) unless options[:metrics]

    usage    "you have specified a username but no password" if username and !password
    usage    "you have specified a password but no username" if password and !username
    verb(    "no queue has been specified, the threshold will be applied to all queues" ) unless queues

rescue ArgumentError => e 
    verb     "invalid arguments, exitting the check"
    usage e 
rescue Exception     => e
    quit :UNKNOWN, "internal error thrown #{e.message}"
end

# ok, everything looks good arguments wise - lets perform the check
begin

    proto           = options[:secure] ? "https" : "http"
    activemq_queues = "#{proto}://#{hostname}:#{port}/admin/xml/queues.jsp"
    response        = nil 

    verb( "attempting to get queue statistics from #{activemq_queues} on queue/s: #{queues}" )
    starttime = Time.now 
    Timeout::timeout( timeout ) {
        opts              = {}
        opts[:basic_auth] = { :username => username, :password => password } if username and password 
        response          = HTTParty.get( activemq_queues, opts )
    }
    endtime   = Time.now
    took      = endtime - starttime
    verb( "activemq api request took #{took}ms")
    
    # ok, we have something? back from activemq - lets check what it is
    verb ( "response code: #{response.response.code}" )
    quit :WARNING, "the username or password incorrect, recieved 401 unauthorized request" if response.response.code.to_i     == 401
    quit :UNKNOWN, "activemq responsed with non 200 http code"                             unless response.response.code.to_i == 200
    # ok, is it valid xml?
    include REXML
    doc = REXML::Document.new( response.response.body )
    total_queues = 0 
    doc.elements.each( 'queues/queue' ) do |q|
        total_queues += 1
    end
    quit :CRITICAL, "unable to find any queues in the xml response from activemq" unless total_queues > 0
    verb( "found #{total_queues} queues in activemq response" ) 
    
    queue_list      = queues.split(',') if queues
    queues_required = queue_list.size   if queue_list
    queues_found    = 0
    perfdata        = "" 
    svcmsg          = "ActiveMQ Queues"
    svcdata         = nil
    nagios_status   = :OK

    doc.elements.each( 'queues/queue' ) do |q|
        queue_name  = q.attributes["name"]
        queue_stats = nil
        q.elements.each( 'stats' ) do |s|   # kind of shitty here, REXL enforces a block, we could override tho
            queue_stats = s.attributes
        end
        verb( "found queue #{queue_name}" )
        # lets skip the queue if we dont care about it
        next if queue_list and !queue_list.include?( queue_name )
        queues_found += 1
        
        if options[:metrics]
            timestamp = Time.now.to_i
            # if we are producing metrics we have to be certain the queue name doesn't contain annoying character
            queue_name = queue_name.gsub( '.', '_' )
            prefix = "#{hostname}.activemq.queue.#{queue_name}"
            puts "#{prefix}.size #{queue_stats['size']} #{timestamp}"
            puts "#{prefix}.enqueueCount #{queue_stats['size']} #{timestamp}"
            puts "#{prefix}.consumerCount #{queue_stats['size']} #{timestamp}"
            puts "#{prefix}.dequeueCount #{queue_stats['size']} #{timestamp}"
        else
            quit :UNKNOWN, "unable to get queue name, probably a error in the xml produced by activemq" unless queue_name  
            quit :UNKNOWN, "unable to get the statistics on queue #{queue_name}, an error in xml?"      unless queue_stats  
            perfdata << "'#{queue_name}_size'=#{queue_stats['size']};#{warning};#{critical}; "
            threshold( "#{queue_name} size", queue_stats['size'], warning, critical ) do |status,message|
                nagios_status = status if nagios_status != :CRITICAL  # if critical, never change 
                svcdata     = "" unless svcdata
                svcdata     << "#{message}, "
            end
        end

    end

    unless options[:metrics]
        unless svcdata
            quit :OK, "#{svcmsg} All Fine | #{perfdata}"
        end
        quit nagios_status, "#{svcmsg} #{svcdata}| #{perfdata}"
    end

rescue Errno::ECONNREFUSED => e
    quit :CRITICAL, "connection to ActiveMQ on port #{options[:port]} was refused"
rescue REXML::ParseException => e
    quit :UNKNOWN, "the response from activemq does not contain valid xml"
rescue Timeout::Error => e
    quit :CRITICAL, "check timed out connecting to activemq, unable to pull activemq queue statistics"
rescue SystemExit => e
    exit e.status 
rescue Exception => e 
    quit :UNKNOWN, "#{__FILE__} threw an internal error,: #{e.message}"
end



