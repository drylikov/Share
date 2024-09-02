#!/usr/bin/ruby 
#
#   Author: Rohith
#   Date: 2013-08-13 10:10:32 +0100 (Tue, 13 Aug 2013)
#
#  vim:ts=4:sw=4:et

$:.unshift File.join(File.dirname(__FILE__),'.','rubylibs')
require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'pp'
require 'optparse'
require 'logging'
require 'nagiosutils'
require 'timeout'
begin
    require 'redis'
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

class RedisCheck

     RedisStats = [ 
        'redis_version', 'uptime_in_seconds', 'connected_clients', 'connected_clients', 'used_memory_peak', 'rdb_changes_since_last_save',
        'rdb_last_save_time', 'rdb_last_bgsave_status', 'rdb_last_bgsave_time_sec', 'total_commands_processed', 'keyspace_hits',
        'keyspace_misses', 'role', 'connected_slaves', 'redis_mode' ]

    def initialize( options ) 
        raise ArgumentError, "no options have been supplied"   unless options
        raise ArgumentError, "no thresholds have been defined" unless options[:thresholds]
        @options = options
        @verbose = options[:verbose]
        @status  = :OK

    end

    def connect( hostname, port = 6379, username = nil, password = nil, timeout = 5 )
    
        redis = nil
        begin
        
            options = {
                :host  => hostname,
                :port  => port
            }
            options[:username] = username if username
            options[:password] = password if password

            verb "connect: attempting to connect to redis instance #{hostname}:#{port}"
            redis = Redis.new( options )
            
        rescue Errno::ECONNREFUSED 
            verb "connect: the request to redis instance #{hostname}:#{port} was refused"
            raise Errno::ECONNREFUSED, "the request to redis instance #{hostname}:#{port} was refused"
        rescue Exception => e 
            verb "connect: redis instance #{hostname}:#{port} threw an exception: #{e.message}"
            raise Exception, e.message
        end 
        redis

    end

    def get_redis_statistics( redis, requires = [] )

        raise ArgumentError, "you have not specified a redis connection" unless redis
        statistics = nil
        begin

            statistics = redis.info    
            verb "statistics=>#{statistics}"
            unless requires.empty?
                lost_keys  = []
                requires.each { |key| lost_keys << key unless statistics[key] }
                raise ArgumentError, "invalid response, the following keys not found in response " << lost_keys.join(',') unless lost_keys.empty?
            end
            raise Exception, "invalid response from statistics, zero results" unless statistics

        rescue ArgumentError => e 
            verb "get_redis_statistics: #{e.message}"
            raise ArgumentError, e.message
        rescue Exception => e 
            verb "get_redis_statistics: #{redis} threw exception, error: #{e.message}"
            raise Exception, e.message
        end
        statistics

    end

    def redis_write( redis, key, value, expire = 0)
        begin
            verb "redis_write: key=>#{key} value=>#{value}"
            start_time = Time.now
            redis.set( key, value )
            time_took  = ( Time.now - start_time ) * 1000
            redis.expire( key, expire ) if expire > 0
            time_took
        rescue Exception => e
            verb "redis_write: failed to perform a write check, error=>" << e.message
            raise Exception, e.message
        end
    end

    def redis_read( redis, key )
        begin
            verb "redis_write: key=>#{key}"
            start_time = Time.now
            result = redis.get( key )
            time_took  = ( Time.now - start_time ) * 1000
            [ time_took, result ]
        rescue Exception => e
            verb "redis_write: failed to perform a write check, error=>" << e.message
            raise Exception, e.message
        end
    end

    def get_database_statistics( info ) 
        space  = info[@options[:database]] 
        quit :CRITICAL, "the statistics for database #{@options[:database]} are invalid" unless space =~ /keys=([0-9]+),expires=([0-9]+)/
        { :keys => $1, :expires => $2 }
    end

    def check_master

        @perfdata = ""
        @servdata = "Redis Master "
        @status   = :OK

        # steps: 
        # - check we can connect to it
        # - if a list of slaves has been supplied, lets make sure they are connection
        # - lets a daily write (used by the slave) - expiring at the end of the day
        # - lets perform a write and read time and measure the times
        # - lets perform any threshold on the instance
        Timeout::timeout( @options[:timeout] ) do

            redis = connect( @options[:hostname], @options[:port], @options[:username], @options[:password] )
            info  = get_redis_statistics( redis, RedisStats )
            @servdata << "mode: #{info['redis_mode']}, role: #{info['role']}, version: #{info['redis_version']}, "
            quit :CRITICAL, "redis instance #{@options[:hostname]} is not a master, present role #{info['role']}" unless info['role'] =~ /^master$/
            # step, if a list of slaves has been supplied, lets make sure they are connection
            if @options[:slaves]
                list = info.select { |key,value| key =~ /^slave[0-9]+/ } 
                verb "found the following slaves on the master #{list}"
                #quit :CRITICAL, "unable to find any connected slaves" if list.empty?
                offline_slaves = []
                slave_list     = []
                list.each do |hash,slave|
                    verb "checking slave #{slave}"
                    quit :CRITICAL, "the slave identify #{slave} is invalid" unless slave =~ /^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+),([0-9]+),(.*)$/
                    unless @options[:slaves].empty?
                        quit :WARNING,  "we have a unknown slave #{$1} attached to master"  unless @options[:slaves].include?( $1 )
                    end
                    slave_host, slave_status = $1, $3
                    offline_slaves << slave_host unless slave_status =~ /^online$/
                    slave_list << slave_host
                end
                quit :WARNING, "the following slaves " << offline_slaves.join(',') << " are offline" unless offline_slaves.empty?
                # create a list of slaves were expecting that are not in the slave list found on master
                slaves_not_found = @options[:slaves].inject([]) do |list,slave|
                    verb "looking for slave #{slave} on master, our slave list is #{slave_list}"
                    list << slave unless slave_list.include?( slave )  
                    list 
                end
                verb "slaves not found on the master #{slaves_not_found} looking for #{@options[:slaves]}"
                quit :CRITICAL, "the following slaves " << slaves_not_found.join(',') << " are not found on the master" unless slaves_not_found.empty?
                
            end
            @servdata << 'slaves: ' << info['connected_slaves'] << ' '
            # step, lets a daily write (used by the slave) - expiring at the end of the day


            # step, lets perform a write and read time and measure the times
            write_key   = "nagios_master_check-" << Time.now.to_s
            write_data  = Time.now.to_s
            write_speed = 0
            read_speed  = 0
            begin 
                write_speed = redis_write( redis, write_key, write_data, 5 )
                @perfdata   << " 'write_ms'=#{write_speed}ms;;"
            rescue Exception => e 
                quit :CRITICAL, "failed to perform a write on redis, error: " << e.message
            end
            # lets read back the key from the instance
            begin 
                read_results = redis_read( redis, write_key )
                read_speed   = read_results.first
                read_result  = read_results.last 
                @perfdata   << " 'read_ms'=#{read_speed}ms;;"
                quit :CRITICAL, "failed to read data back from redis, result = nil"        unless read_result 
                quit :CRITICAL, "failed to read data back from redis, result is different" unless read_result == write_data
            rescue Exception => e
                quit :CRITICAL, "failed to read back data from redis, error: " << e.message
            end

            # step, lets validate against the thresholds or the defaults
            if @options[:thresholds]
                @options[:thresholds].each do |key,value|
                    next unless info[key]
                    threshold( value[:label] || key.to_s, info[key], value[:warning] || nil, value[:critical] || nil ) do |status,message|
                        @servdata << "#{message}"
                    end
                end
            end

            if @options[:database]
                info = get_database_statistics( info )
                @perfdata << " '#{@options[:database]}_keys'=" << info[:keys] << ';;'
            end

            # step, lets include any performance data
            [ 'connected_slaves', 'connected_clients', 'used_memory_peak', 'rdb_changes_since_last_save' ].each do |item|
                @perfdata << " '#{item}'=" << info[item] << ';;'
            end

            quit @status, @servdata << " | " << @perfdata

        end

    end

    def check_slave

        @perfdata = ""
        @servdata = "Redis Slave "
        @status   = :OK

        # steps: 
        # - check we can connect to it
        # - check we are a slave and connected to a master
        # - check we and read the master keys
        # - lets perform any threshold on the instance

        Timeout::timeout( @options[:timeout] ) do

            redis = connect( @options[:hostname], @options[:port], @options[:username], @options[:password] )
            info  = get_redis_statistics( redis, RedisStats )
            @servdata << "mode: #{info['redis_mode']}, role: #{info['role']}, version: #{info['redis_version']}: "

            # step, check we are a slave and connected to a master
            quit :CRITICAL, "instance is not a slave, present role #{info['role']}"  unless info['role'] =~ /slave/
            quit :CRITICAL, "the redis slave does not have a master specified"       unless info['master_host']
            @servdata << "master: #{info['master_host']}"
            if @options[:master]
                quit :CRITICAL, "the slave connected to wrong master, expected #{@options[:master]}, founed #{info['master_host']}" unless info['master_host'] =~ /#{@options[:master]}/
            end
            master = info['master_host']
            quit :CRITICAL, "the link between slave and master #{master} is down"    unless info['master_link_status'] =~ /^up$/

            # step, check we and read the master keys


            # step, lets perform any threshold on the instance
            if @options[:thresholds]
                @options[:thresholds].each do |key,value|
                    next unless info[key]
                    threshold( value[:label] || key.to_s, info[key], value[:warning] || nil, value[:critical] || nil ) do |status,message|
                        @servdata << "#{message}"
                    end
                end
            end

            if @options[:database]
                info = get_database_statistics( info )
                @perfdata << " '#{@options[:database]}_keys'=" << info[:keys] << ';;'
            end

            # step, lets include any performance data
            [ 'master_last_io_seconds_ago', 'connected_clients', 'used_memory_peak', 'rdb_changes_since_last_save', 'rdb_last_save_time' ].each do |item|
                @perfdata << " '#{item}'=" << info[item] << ';;'
            end

            quit @status, @servdata << " | " << @perfdata

        end

    end

    def check_queue

        begin

            @perfdata = ""
            @servdata = "Redis Queue, "
            @status   = :OK
            
            Timeout::timeout( @options[:timeout] ) do

                redis  = connect( @options[:hostname], @options[:port], @options[:username], @options[:password] )
                result = redis.llen( @options[:queue] )
                quit :CRITICAL, "unable to get the queue length" unless result
                @servdata << "name = %s, "    % [ @options[:queue] ]
                @servdata << "length = %d "   % [ result ]
                @perfdata = "'%s'=%d;%s;%s;" % [ @options[:queue], result, @options[:warning] || '', @options[:critical] || '' ] 

                threshold( "queue" , result, @options[:warning] || nil, @options[:critical] || nil ) do |status,message|
                    @servdata << "#{message}"
                end
                quit @status, "%s | %s" % [ @servdata, @perfdata ]

            end
            
        rescue Errno::ECONNREFUSED => e 
            verb "check_queue: connection refuse to #{hostname}:#{port}"
            raise Errno::ECONNREFUSED, "connection refused to redis instance #{hostname}:#{port}"
        rescue Timeout::Error 
            verb "check_queue: check timed out after #{@options[:timeout]} seconds"
            raise Timeout::Error, "unable to perform check on redis #{hostname}:#{port}, timed out after #{@options[:timeout]} seconds"
        rescue SystemExit => e
            raise 
        rescue Exception => e
            quit :CRITICAL, e.message
        end

    end

    def check_instance

        begin 

            @perfdata = ""
            @servdata = "Redis Instance "
            @status   = :OK
            
            Timeout::timeout( @options[:timeout] ) do

                redis = connect( @options[:hostname], @options[:port], @options[:username], @options[:password] )
                info  = get_redis_statistics( redis, RedisStats )
                @servdata << "mode: #{info['redis_mode']}, role: #{info['role']}, version: #{info['redis_version']}: "

                # step, lets validate against the thresholds or the defaults
                @options[:thresholds].each do |key,value|
                    next unless info[key]
                    threshold( value[:label] || key.to_s, info[key], value[:warning] || nil, value[:critical] || nil ) do |status,message|
                        @servdata << "#{message}"
                    end
                end

               # step, lets perform a write and read time and measure the times
               unless info['role'] == 'slave'
                   write_key   = "nagios_instance_check-" << Time.now.to_s
                   write_data  = Time.now.to_s
                   write_speed = 0
                   read_speed  = 0
                   begin 
                       write_speed = redis_write( redis, write_key, write_data, 5 )
                       @perfdata   << " 'write_ms'=#{write_speed}ms;;"
                   rescue Exception => e 
                       quit :CRITICAL, "failed to perform a write on redis, error: " << e.message
                   end
                   # lets read back the key from the instance
                   begin 
                       read_results = redis_read( redis, write_key )
                       read_speed   = read_results.first
                       read_result  = read_results.last 
                       @perfdata   << " 'read_ms'=#{read_speed}ms;;"
                       quit :CRITICAL, "failed to read data back from redis, result = nil"        unless read_result 
                       quit :CRITICAL, "failed to read data back from redis, result is different" unless read_result == write_data
                   rescue Exception => e
                       quit :CRITICAL, "failed to read back data from redis, error: " << e.message
                   end
                end

                if @options[:database]
                    quit :CRITICAL, "the database #{@options[:database]} does not exist"             unless info[@options[:database]]
                    space  = info[@options[:database]] 
                    quit :CRITICAL, "the statistics for database #{@options[:database]} are invalid" unless space =~ /keys=([0-9]+),expires=([0-9]+)/
                    @perfdata << " '#{@options[:database]}_keys'=#{$1};;"
                end

                [ 'connected_clients', 'used_memory_peak', 'rdb_changes_since_last_save', 'rdb_last_save_time' ].each do |item|
                    @perfdata << " '#{item}'=" << info[item] << ';;' if info[item]
                end
 
                quit @status, @servdata << " | " << @perfdata

            end

        rescue Errno::ECONNREFUSED => e 
            verb "check_instance: connection refuse to #{hostname}:#{port}"
            raise Errno::ECONNREFUSED, "connection refused to redis instance #{hostname}:#{port}"
        rescue Timeout::Error 
            verb "check_instance: check timed out after #{@options[:timeout]} seconds"
            raise Timeout::Error, "unable to perform check on redis #{hostname}:#{port}, timed out after #{@options[:timeout]} seconds"
        rescue SystemExit => e
            raise 
        rescue Exception => e
            quit :CRITICAL, e.message
        end

    end


end

thresholds = {
    "uptime_in_seconds" => {
        :warning   => ":300",
        :critical  => ":500"
    },
    "connected_clients" => {
        :critical  => "320",
        :warning   => ":1"
    },
    "mem_fragmentation_ratio" => {
        :warning   => "10",
        :critical  => "20"
    },
    "blocked_clients" => {
        :warning   => "15"
    },
    "rdb_changes_since_last_save" => {
        :warning   => "3000",
        :critical  => "5000"
    },
#    "master_last_io_seconds_ago" => {
#        :warning   => 30,
#        :critical  => 60
#    },
    "slave_read_only" => {
        :critical  => 1
    }
}


RedisCheckTypes = [ 'instance', 'master', 'slave', 'queue' ]
options = {
    :port       => 6379,
    :timeout    => 10,
    :thresholds => thresholds,
    :slaves     => [],
    :username   => nil,
    :password   => nil,
    :verbose    => false,
    :warning    => 30,
    :critical   => 50,
}
custom_thresholds = []

Parser = OptionParser::new do |opts|
    opts.on( "-H", "--host hostname",       "the hostname | ip address of the redis instance" )              { |arg| options[:hostname]     = arg    }
    opts.on( "-p", "--port port",           "the port of the redis instance" )                               { |arg| options[:port]         = arg    }
    opts.on( "-t", "--timeout secs",        "the timeout in seconds for the check" )                         { |arg| options[:timeout]      = arg    }
    opts.on( "-T", "--threshold threshold", "the threshold for a parameters, name,w=<v>,c=<v>" )             { |arg| custom_thresholds      << arg   }
    opts.on( "-s", "--slave hostname",      "a slave that should be attached to master" )                    { |arg| options[:slaves]       << arg   }
    opts.on( "-q", "--queue name",          "check the queue length" )                                       { |arg| options[:queue]        = arg    } 
    opts.on( "-m", "--master hostname",     "a master that should be attached to slave" )                    { |arg| options[:master]       = arg    }
    opts.on( "-d", "--database name",       "the name of any database you wish to check the keyspace on")    { |arg| options[:database]     = arg    }
    opts.on( "-U", "--username user",       "the username to connect to the redis instance" )                { |arg| options[:username]     = arg    }
    opts.on( "-P", "--password pass",       "the password to connect to the redis instance" )                { |arg| options[:password]     = arg    }
    opts.on( "-W", "--warning value",       "the threshold for warnings" )                                   { |arg| options[:warning]      = arg    }
    opts.on( "-C", "--critical value",      "the threshold for criticals" )                                  { |arg| options[:critical]     = arg    }
    opts.on( "-c", "--check type",          "the check type, master|slave|instance|metrics" )                { |arg| options[:check]        = arg    }
    opts.on( "-v", "--verbose",             "switch on verbose logging" )                                    { options[:verbose]            = true   }
end
Parser.parse!

# lets validate the arguments
begin

    options[:hostname] = validate_hostname( options[:hostname] )
    options[:port]     = validate_port( options[:port] )
    options[:timeout]  = validate_timeout( options[:timeout], 10, 60 )
    options[:master]   = validate_hostname( options[:master] )   if options[:master]
    options[:username] = validate_username( options[:username] ) if options[:username]
    options[:password] = validate_password( options[:password] ) if options[:password]
    options[:slaves].map do |slave|
        validate_hostname( slave )
    end

    raise ArgumentError, "invalid check type specified" unless RedisCheckTypes.include?( options[:check] )

    if options[:type] == 'queue'
        raise ArgummentError, "you have not specified a queue name to check" unless options[:queue]
        options[:warning]  = validate_threshold( options[:warning] ) if options[:warning]
        options[:critical] = validate_threshold( optoins[:critical]) if options[:critical]
    end

    # we need to validate any custom thresholds
    unless custom_thresholds.empty?
        custom_thresholds.inject( thresholds ) do |list, t|
            attributes = t.split( ',')
            raise ArgumentError, "invalid threshold #{t}" unless attributes.size >= 2
            name = t.split( ',').first
            attributes.each do |item|
                next unless item =~ /^([wcWC])=(.*)$/
                #raise ArgumentError, "invalid threshold #{item} specified for #{threshold_name}" unless item =~ /^([wcWC])=(.*)$/
                list[name] = {} unless list[name]
                case $1.downcase
                when 'w'
                    list[name][:warning]  = $2
                when 'c'
                    list[name][:critical] = $2
                end
            end
            list
        end 
    end

rescue ArgumentError => e
    usage e.message
rescue Exception     => e
    quit :CRITICAL, "internal error processing the command line options, error: " << e.message
end

begin

    check = RedisCheck::new( options )
    case options[:check]
    when 'instance'
        check.check_instance
    when 'master'
        check.check_master 
    when 'slave'
        check.check_slave
    when 'queue'
        check.check_queue
    end

rescue Errno::ECONNREFUSED, Timeout::Error => e 
    quit :CRITICAL, e.message
rescue SystemExit => e
    exit e.status 
rescue Exception => e 
    quit :UNKNOWN, "#{__FILE__} threw an internal error,: #{e.message}"
end

