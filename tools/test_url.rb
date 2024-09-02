#!/usr/bin/ruby
# 
# desc: a simple script used to poll a http url
#

require 'rubygems'
require 'optparse'
require 'httparty'
require 'pp'

Meta = {
    :prog    => __FILE__,
    :author  => "Rohith Jayawardene",
    :email   => "gambol99@gmail.com",
    :version => "0.0.1"
}

class URLChecker

    include HTTParty
    #debug_output $stderr
    attr_reader :options, :counter, :stats    

    def initialize( options )

        raise ArgumentError, "you haven't passed any options" unless options
        @options = options
        @counter = 0
        @count   = @options[:count]
        @stats   = {
            :requests => 0, 
            :success  => 0, 
            :total    => 0, 
            :avg      => 0, 
            :min      => 1000000, 
            :max      => 0, 
            :timeouts => 0 
        }
        @url_length = @options[:url].length + 2

    end

    def process

        begin
                
            
            while @counter < @options[:count] or @options[:count] == 0 
                                
                begin

                    @stats[:requests] += 1
                    start    = Time.now
                    response = self.class.get( @options[:url], { :timeout => @options[:timeout] } )
                    endtime  = Time.now
                    time_ms  = ( endtime - start ) * 1000
                    update_status( time_ms, response, true )
        
                rescue Timeout::Error => e

                    update_status( 0.0, nil, false )

                end

                sleep( @options[:interval] )
                @counter += 1

            end
 
        rescue SystemExit, Interrupt => e

            puts "..."

        rescue Exception => e

            puts "process: threw an exception: #{e.message}" 
            raise
            
        end
        self.print_statistics( @stats )

    end

    def update_status( response_time_ms = 0.0, response = nil, success = true )

        length = @url_length
        status = "%-4d %-14s %#{length}s " % [ @counter, Time.now.strftime("%H:%M:%S.%L"), @options[:url] ]
        if success == false
            status << "the request timed out"
            @stats[:timeouts] += 1
        else
            status << "%6.2fms %4s" % [ response_time_ms, response.code ]
            if @options[:show]
                if response.body.length <= 32 
                    status << " %10s: %-32s\n"   % [ "output", response.body.chomp ]
                else
                    status << "\noutput:\n%s\n" % [ response.body.chomp ]
                end
            end
            @stats[:success]  += 1
            @stats[:min]      = response_time_ms if response_time_ms < @stats[:min]
            @stats[:max]      = response_time_ms if response_time_ms > @stats[:max]
            @stats[:total]    += response_time_ms 
        end
        puts status

    end

    def print_statistics( stats ) 

        if stats[:success] >= 1 
            requests, success, fails, min, max, avg = stats[:requests], stats[:success], stats[:timeouts], stats[:min], stats[:max], ( stats[:total] / stats[:requests] )
            print "\nrequests: %d, success: %d, fails: %d - avg:%4.2fms, min:%4.2fms, max:%4.2fms\n" % [ requests, success, fails, avg, min, max ] 
        end

    end


end

options = {
    :interval => 0.5,
    :timeout  => 3,
    :show     => false,
    :count    => 0
}
# lets get the options
parser = OptionParser::new do |o|
    o.banner = "Usage: %s -u|--url -t|--timeout secs" % [ Meta[:prog] ]
    o.on( "-u", "--url url",          "the url to be tested"    )          { |arg|  options[:url]      = arg       }
    o.on( "-i", "--interval seconds", "the interval between checks" )      { |arg|  options[:interval] = arg.to_f  }
    o.on( "-c", "--count iterations", "the number of calls to make" )      { |arg|  options[:count]    = arg.to_i  }
    o.on( "-t", "--timeout secs ",    "the timeout per request" )          { |arg|  options[:timeout]  = arg.to_i  }
    o.on( "-o", "--output",           "show the output from the request" ) {        options[:show]     = true }
    o.on( "-V", "--version",          "display the version information"  ) do
        puts "%s written by %s ( %s ) version: %s\n" % [ Meta[:prog], Meta[:author], Meta[:email], Meta[:version] ]
        exit 0
    end
end
parser.parse!

# check we have all the options
mopt = lambda { |msg| 
    puts "%s\nerror: %s" % [ parser, msg ] 
    exit 1 
}
mopt.call "you have not specified a url to call" unless options[:url]
mopt.call "the timeout must numeric" unless options[:timeout].is_a?( Integer) or options[:timeout] > 1

begin

    checker = URLChecker::new( options )
    checker.process

rescue Exception => e

    puts "an exception was thrown, error: #{e.message}"
    exit 1

end

