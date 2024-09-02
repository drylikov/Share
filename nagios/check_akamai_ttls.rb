#!/usr/bin/ruby 
#
#   Author: Rohith
#   Date: 2013-08-15 19:51:32 +0100 (Thu, 15 Aug 2013)
#
#  vim:ts=4:sw=4:et
#

$:.unshift File.join(File.dirname(__FILE__),'.','rubylibs')
require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'pp'
begin 
    require "em-synchrony"
    require "em-synchrony/em-http"
rescue Exception => e
    puts "module dependency error: this plugin requires #{e.message}"
    exit 1
end
require 'optparse'
require 'yaml'
require 'timeout'
require 'logging'
require 'nagiosutils'

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
    :date     => "2013-08-15 19:53:32 +0100",
    :version  => "0.0.1"
}

class CachePageChecker

    include Logging

    TTL = {
        's' => 1,
        'm' => 60,
        'h' => 3600,
        'd' => 86400,
        'w' => 604800
    }

    attr_accessor :stats, :options

    def initialize( options = {} )
        @verbose,@options  = options[:verbose], options
        @stats     = {
            :total_requests   => 0,
            :invalid_urls     => [],
            :request_timeouts => [],
            :nocache_errors   => [],
            :pages_errors     => [],
            :cache_errors     => []
        }
        @request_options = {
            :redirects          => 0,
            :connect_timeout    => @options[:request_timeout], 
            :inactivity_timeout => @options[:request_timeout]
        }
    end

    def getTTL( spec )
        if spec =~ /^([0-9]+)([smhdw])$/
            age = ( $1.to_i * TTL[$2] )
            age
        end
    end

    def run

        verb( "run: kicking off the reator loop" )
        starttime = Time.now
        EM.synchrony do
            @verbose = @options[:verbose]
            @options[:urls].each do |group|
                raise Exception, "invalid group, please check the urls input, as it does not contain a group name"  unless group[:name]
                raise Exception, "invalid group #{group[:name]}, does not contain a cache ttl, please check inputs" unless group[:ttl]
                raise Exception, "invalid cache ttl #{group[:ttl]} specified for on cache group #{group}"           unless group[:ttl] =~ /^[0-9]+[smhdw]$/ 
                expected_age  = getTTL( group[:ttl] )
                EM::Synchrony::Iterator.new( group[:urls], @options[:concurrency] ).map do |uri, iter|
                    @stats[:total_requests] += 1
                    
                    url = "http://#{options[:hostname]}#{uri}"
                    verb( "(e) %-8d (c) #{url}" % [ expected_age ] )
                    
                    http = EventMachine::HttpRequest.new(url).aget
                    http.callback { 
                        verb( "url:#{url} cache header: #{http.response_header['CACHE_CONTROL']}" )
                        if http.response_header['CACHE_CONTROL']                       
                            unless http.response_header['CACHE_CONTROL'] =~ /(max-age)=([0-9]+)/
                                verb( "invalid: page has not cache headers #{url}" )
                                @stats[:nocache_errors] << url
                                iter.return(http)
                            end
                            max_age = $2.to_i
                            if @options[:fuzzy]

                            else
                                unless max_age == expected_age
                                   verb( "invalid cache ttl, expecting: #{expected_age} found: #{max_age} url #{url}" )
                                   @stats[:cache_errors]   << { :url => url, :ttl => max_age, :expected => expected_age } 
                                end
                            end   
                        else
                            @stats[:nocache_errors] << url
                        end
                        iter.return(http) 
                    }
                    http.errback { 
                        @stats[:pages_errors] << url
                        verb( "page error on #{url}" )
    		            iter.return(http) 
                    }
                end
            end 
            EM.stop
        end
        endtime       = Time.now
        time_took     = ( endtime - starttime )
        PP.pp stats, stats_pp = ""
        verb( "statistics:\n #{stats_pp}" )
        verb( "processed requests in %f ms" % [ time_took ] )
        @stats[:time] =( endtime - starttime )  
        @stats

    end

end

options = { 
    :hostname         => nil,
    :urls             => nil,
    :timeout          => 300,
    :concurrency      => 100,
    :request_timeout  => 5,
    :verbose          => false,
    :fuzzy            => false,
    :warncache       => "1",
    :critcache       => "1",
    :warnerror       => "10",
    :criterror       => "20"
}
@verbose = false;

Parser = OptionParser::new do |opts|
    opts.on( "-H", "--hostname hostname",    "set the hostname for the checks, (defaults to #{options[:hostname]})" )          { |arg| options[:hostname]        = arg    }
    opts.on( "-U", "--urls file",            "the files containing the urls to trace. otherwise we read from stdin" )          { |arg| options[:urls]            = arg    }
    opts.on( "-t", "--timeout secs",         "the timeout of the entire check (defaults to #{options[:timeout]})" )            { |arg| options[:timeout]         = arg    }
    opts.on( "-c", "--concurrency num",      "the number of concurrent requests (defaults to #{options[:concurrency]})" )      { |arg| options[:timeout]         = arg    }
    opts.on( "-f", "--fuzzy",                "applying fuzzy caches (read notes) (defaults to false)" )                        { |arg| options[:fuzzy]           = true   }             
    opts.on( "-T", "--request-timeout secs", "the timeout per request (defaults to #{options[:request_timeout]})" )            { |arg| options[:request_timeout] = arg    }
    opts.on( "--warnerror num",        "the warning threshold for page errors (defaults to #{options[:warnerror]})" )   { |arg| options[:warnerror]      = arg    }
    opts.on( "--warncache num",        "the warning threshold for cache errors (defaults to #{options[:warncache]})" )  { |arg| options[:warncache]      = arg    }
    opts.on( "--criterror num",        "the critical threshold for page errors (defaults to #{options[:criterror]})" )  { |arg| options[:criterror]      = arg    }
    opts.on( "--critcache num",        "the critical threshold for cache errors (defaults to #{options[:critcache]})" ) { |arg| options[:critcache]      = arg    }
    opts.on( "-v", "--verbose",              "switch on verbose logging" )                                                     { options[:verbose]               = true   }
end
Parser.parse!

@verbose  = options[:verbose]     

begin

    options[:urls]             = validate_filename( options[:urls], "urls" )
    options[:timeout]          = validate_integer(  options[:timeout], 30, 300, "timeout" )
    options[:request_timeout]  = validate_integer(  options[:request_timeout], 2, 30, "request timeout" )
    options[:concurrency]      = validate_integer(  options[:concurrency], 2, 1000, "concurrency" )
    options[:warncache]       = validate_threshold( options[:warncache], "warncache" ) if options[:warncache]
    options[:critcache]       = validate_threshold( options[:critcache], "critcache" ) if options[:critcache]
    options[:warnerror]       = validate_threshold( options[:warnerror], "warnerror" ) if options[:warnerror]
    options[:criterror]       = validate_threshold( options[:criterror], "criterror" ) if options[:criterror]

    # lets load the yaml file
    options[:urls]             = YAML.load_file( options[:urls] )

rescue ArgumentError => e
    usage e.message
rescue Exception     => e 
    usage "a internal error occured, error: #{e.message}"
end

# ok, everything looks good arguments wise, lets perform the check
begin
    verb( "performing the cache validation now" )
    stats = nil
    Timeout::timeout( options[:timeout] ) do
        stats = CachePageChecker::new( options ).run
    end
    
    # lets perform the thresholds on the results
    @status       =  :OK
    perfdata      =  ""
    servdata      =  "Cache TTLs: cache_errors: #{stats[:cache_errors].size}, page_errors: #{stats[:pages_errors].size}"
    cache_alerts  =  stats[:cache_errors][1..5].map { |e| "url: #{e[:url]} expected: #{e[:expected]} ttl: #{e[:ttl]}\n" }.join
#    pages_alerts |= "" << stats[:pages_errors][1..5].map{ |e| e }.join("\n")

    threshold( "Cache Errors", stats[:cache_errors].size, options[:warncache], options[:critcache] ) 
    threshold( "Page Errors",  stats[:pages_errors].size, options[:warnerror], options[:criterror] ) 

    quit @status, "#{servdata}\n" << cache_alerts #<< pac_errors

rescue Timeout::Error => e 
    quit :CRITICAL, "the check has taken too long and has timed out after #{options[:timeout]} secs"
rescue Interrupt 
    quit :OK, "quitting the check at user request"
rescue SystemExit => e 
    exit e.status
rescue Exception  => e 
    quit :UNKNOWN,  e.message
end
    


