#!/usr/bin/ruby 
#
#   Author: Rohith
#   Date: 2013-08-27 11:10:08 +0100 (Tue, 27 Aug 2013)
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
require 'json'
require 'nagiosutils'
require 'timeout'

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
    :date     => "2013-08-27 11:10:08 +0100",
    :version  => "0.0.1"
}

class ElasticSearchCheck

    include HTTParty
    include Logging
    include NagiosUtils


    def initialize( options )
        @options = options
        @verbose = options[:verbose] || false
        @status  = :OK
    end

    def elastic_request( url, timeout = 10, opts = {}, json = true )
        raise ArgumentError, "you have not specified a url to call" unless url
        response = nil
        begin
            Timeout::timeout( timeout ) do
                verb "elastic_request: requesting url #{url}"
                response = HTTParty.get( url, opts )
                response = JSON.parse( response.response.body ) if json
            end
        rescue JSON::ParserError => e
            quit :CRITICAL, "the response from #{url} is not valid json, error: #{e.message}"
        rescue Timeout::Error 
            quit :CRITICAL, "the response from elasticsearch has exceeded the timeout of #{timeout} seconds"
        rescue Errno::ECONNREFUSED 
            quit :CRITICAL, "the request to elasticsearch has been refused"
        rescue Exception => e 
            verb "elastic_request: url=>#{url} threw en exception: #{e.message}"
            raise Exception, e.message
        end 
        response
    end

    def check_cluster( list = [] )
        begin
            cluster_health = "http://#{@options[:hostname]}:#{@options[:port]}/_cluster/health"

            # step, ok - lets get the cluster health
            result = elastic_request( "#{cluster_health}?level=cluster", @options[:timeout] )
            @status = :OK
            service_data = "Elasticsearch: "
            # lets check the status from the cluster health
            quit :CRITICAL, "the response from elasticsearch looks invalid, does not have a cluster name" unless result['cluster_name']
            quit :CRITICAL, "invalid response from elasticsearch, does not contain number_of_nodes"       unless result['number_of_nodes']
            quit :CRITICAL, "invalid response from elasticsearch, does not contain number_of_data_nodes"  unless result['number_of_data_nodes']
            quit :CRITICAL, "invalid response from elasticsearch, does not contain a status"              unless result['status']
            quit :CRITICAL, "the response of cluster status is invalid" unless [ 'yellow', 'red', 'green' ].include?( result['status'] )
            service_data << "Cluster: '#{result['cluster_name']}' "
            quit :WARNING,  "the cluster status is warning"  if result['status'] =~ /yellow/
            quit :CRITICAL, "the cluster status is critical" if result['status'] =~ /red/
            # name, value, warning, critical, &block 
            threshold( 'cluster nodes',      result['number_of_nodes'], nil,      @options[:nodes] ) do |state,message| 
                service_data << " " << message
            end
            threshold( 'cluster data nodes', result['number_of_data_nodes'], nil, @options[:data_nodes] ) do |state,message|
                service_data << " " << message
            end
            threshold( 'unassigned shards',  result['unassigned_shards'], nil, 1 ) do |state,message|
                service_data << " " <<  message
            end
            threshold( 'active_shards',      result['active_shards'], nil, ":1"  ) do |state,message|
                service_data << " " << message
            end
            service_data << "All Good" if @status == :OK

            # lets check the indices health
            result = elastic_request( "#{cluster_health}?level=indices", @options[:timeout] )
            quit :CRITICAL, "the response of cluster status is invalid" unless [ 'yellow', 'red', 'green' ].include?( result['status'] )
            if result['status'] != 'green'
                faulty_index = [] 
                result['indices'].each do |index|
                    next if index.last['status'] == 'green'
                    faulty_index << { :index => index.first, :status => index.last['status'] }
                end
                service_data << "faulty index on "
                faulty_index.each do |index|
                    service_data << "%s status:%s " % [ index[:index], index[:status] ]
                end
            else
                service_data << ", Indices: All Green"
            end

            quit @status, service_data

        rescue SystemExit => e
            raise 
        rescue Exception => e 
            quit :CRITICAL, "an internal error occured trying to process the check, error: #{e.message}"
        end
    end

end


# lets set the defaults first of all
options = { 
    :hostname     => 'localhost',
    :port         => 9200,
    :timeout      => 10,
    :verbose      => false,
    :metrics      => false,
    :check        => :instance
}
@verbose = options[:verbose]

# lets get the options
Parser = OptionParser::new do |opts|
    opts.on( "-H", "--host hostname",      "the hostname | ip address of the elasticsearch instance" )              { |arg| options[:hostname]     = arg      }
    opts.on( "-p", "--port port",          "the port activemq is running on (defaults to #{options[:port]})")       { |arg| options[:port]         = arg      }
    opts.on( "-C", "--cluster",            "perform a cluster check of the elasticsearch" )                         { |arg| options[:check]        = :cluster }
    opts.on( "-I", "--indices [list]",     "perform a index check of the elasticsearch" ) do |arg|
        options[:check] = :indices
        options[:list]  = arg || nil 
    end
    opts.on( "-S", "--shards  [list]",     "perform a shards check of the elasticsearch cluster" ) do |arg|
        options[:check] = :shards
        options[:list]  = arg || nil 
    end
    opts.on( "--nodes num",                "the expected number of nodes in the cluster")                           { |arg| options[:nodes]        = arg      }
    opts.on( "--data-nodes num"            "the expected number of data nodes in the cluster")                      { |arg| options[:data_nodes]   = arg      }
    opts.on( "-t", "--timeout timeout",    "the critical threshold of queue count" )                                { |arg| options[:timeout]      = arg      }
    opts.on( "-M", "--metrics",            "produce metrics only on the queues, no thresholding" )                  { |arg| options[:metrics]      = true     }
    opts.on( "-v", "--verbose",            "switch on verbose logging" )                                            { |arg| options[:verbose]      = true     }
end
Parser.parse!

# lets validate the arguments
begin
    
    @verbose = options[:verbose] if options[:verbose]
    options[:hostname]   = validate_hostname( options[:hostname] )
    options[:port]       = validate_port( options[:port] )
    options[:timeout]    = validate_timeout( options[:timeout], 5, 60 )
#    options[:nodes]      = validate_integer( options[:nodes], 1, 1000, "expected nodes" )           if options[:nodes]
#    options[:data_nodes] = validate_integer( options[:data_nodes], 1, 1000, "expected data nodes" ) if options[:data_nodes]
    
    if options[:check] == :cluster
        raise ArgumentError, "you need to specify the expected number of nodes in the cluster"      unless options[:nodes]
        raise ArgumentError, "you need to specify the expected number of data nodes in the cluster" unless options[:data_nodes]
    elsif options[:check] == :indices

    elsif options[:check] == :shards

    else
        raise ArgumentError, "unknown check type #{options[:check]}"
    end 
   
rescue ArgumentError => e 
    usage e 
rescue Exception     => e
    quit :UNKNOWN, "internal error thrown #{e.message}"
end

# ok, lets perform the check
begin 

    elastic = ElasticSearchCheck::new( options )
    verb "attempting to check #{options[:hostname]}:#{options[:port]} to perform a #{options[:check].to_s} check"   
    case options[:check]
    when :cluster
        elastic.check_cluster
    when :indices
        elastic.check_indices
    when :shards
        elastic.check_shards
    end

rescue Errno::ECONNREFUSED => e
    quit :CRITICAL, e.message
rescue Timeout::Error => e
    quit :CRITICAL, e.message
rescue SystemExit => e
    exit e.status 
rescue Exception => e 
    quit :UNKNOWN, "#{__FILE__} threw an internal error,: #{e.message}"
end




