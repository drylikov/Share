#!/usr/bin/ruby
#
# desc: the flock command is a generic handler used to run a set of commands under a atomic lock file
# 

require 'rubygems'
require 'optparse'
require 'timeout'

Meta = {
   :prog	=> "#{__FILE__}",
   :author	=> "Rohith",
   :email	=> "gambol99@gmail.com",
   :version	=> "0.0.1"
}

$Default_timeout = 30
$Default_lock    = "/tmp/flock.lock"

class FlockHandle

    attr_accessor :options

    def initialize( args ) 
        @options = args
        log "commands=>\"%s\" timeout=>%d" % [ @options[:command], @options[:timeout ] ]
    end

    def log( msg = nil ) 
        puts "v: (flock) #{msg}" if msg and @options[:verbose]
    end

    def execute 
        log "execute: lock=>%s commands=>%s" % [ @options[:lock], @options[:command] ]
        lock = nil
        begin

            cmd = @options[:command]
            Timeout::timeout( @options[:timeout] ) {
                lock = File.open( @options[:lock], File::RDWR | File::CREAT , 0644 ) 
                lock.flock( File::LOCK_EX ) 
            }
            log "execute: acquired the lock"
            %x( #{cmd} ) 
            File.delete( @options[:lock] ) 
    
        rescue Timeout::Error => e
            log "execute: exceeded timeout %d secs, trying to acquire lock #{e.message}" % [ @options[:timeout] ]
            raise Timeout::Error, "exceeded timeout to acquire the lock" 
        rescue Exception => e
            log "execute: failed to execution #{e.message}"
            raise
        end
    end
end

options = {}
options[:timeout] ||= $Default_timeout
options[:lock]    ||= $Default_lock
options[:verbose] ||= false

parser = OptionParser::new do |opts|
    opts.banner = "Usage: %s -c <command> -t <timeout> -l <lock file path>" % [ Meta[:prod] ]
    opts.on( "-c", "--command=<command>",  "the command/s you wish to run under lock" )                  { |arg| options[:command]  = arg }  
    opts.on( "-l", "--lock=<lock file>",   "the path of the lock file you wish to use")                  { |arg| options[:lock]     = arg }
    opts.on( "-t", "--timeout=seconds",    "the timeout fot wait on local, default #$Default_timeout") do |arg|
        puts "invalid timeout, must be a integer" unless /^[0-9]$/ =~ arg
        options[:timeout] = arg.to_i
    end 
    opts.on( "-v", "--verbose",            "set verbose mode" )                                          { options[:verbose] = true       }
    opts.on( "-V", "--version",            "display the version" ) do
        puts "Written by %s (%s) version: %s" % [ Meta[:author], Meta[:email], Meta[:version] ]
        exit 0
    end
end
parser.parse!

unless options[:command]
    puts parser
    puts "\nerror: you need to specify a set of commands to run"
end

begin 
 
    flock = FlockHandle::new( options )
    flock.execute

rescue Timeout::Error => e
 
    puts "flock: unable to acquire the exclusive lock, exceeded timeout of #{options[:timeout]}"
    exit 1

rescue Exception => e

    puts "flock: exception encountered: error #{e.message}"
    exit 1    

end

exit 0
