#!/usr/bin/ruby -w
#
#   Author: Rohith
#   Date: 2013-08-13 10:10:32 +0100 (Tue, 13 Aug 2013)
#
#  vim:ts=4:sw=4:et

module CrucialUtils

    @@codes = {
        :OK         => 0,
        :WARNING    => 1,
        :CRITICAL   => 2,
        :UNKNOWN    => 3
    }

    @@regexes = {
        :username   => ".*",
        :password   => ".*",
        :threshold  => "^(:[0-9]+|[0-9]+)$",
        :float      => "^[-+]?[0-9]*\.?[0-9]+$",
        :integer    => "^[0-9]+$",
        :hostname   => ".*"
    }

    def verbose
        @verbose = false
    end

    def log( level, message )
        puts "%-5s %s" % [ "[#{level}]:", message ] if message
    end
    
    def verb( message )
        log "verb", message if @verbose
    end

    def info( message )
        log "info", message
    end

    def warn( message) 
        log "warn", message
    end

    def error( message )
        log "error", message
    end

    def usage( message ) 

        puts "\n%s\n" % [ Parser ] 
        if message
            puts "error: %s\n" % [ message ]
            exit 1
        end
        exit 0

    end

    class ::String

        Expand_Regex = /([{,])([^{},]*){([^{}]+)}([^{},]*)([,}])/

        def expand( result = [''] )
            self.sub!( Expand_Regex ) {
                $1 << $3.split(',').map { |i|
                    $2<<i<<$4
                }.join(",") << $5
            } while match Expand_Regex
            self.scan(/([^{}]*){([^{}]+)}([^{}]+$)?/) { |a,b,e| result = result.product( b.split(',').map {|c|  a.to_s + c + e.to_s}).collect {|x,y| x + y} }
            result
        end
    end

    def get_ttl( spec )
        if spec =~ /^([0-9]+)([smhdw])$/
            age = ( $1.to_i * TTL[$2] )
            age
        end
    end

    def to_float( value ) 
        value = value.to_f if value.is_a?( Integer )
        if value.is_a?( String )
            raise ArgumentError, "invalid integer / float cannot be converted" unless value =~ /^[0-9\.]+$/        
            value = value.to_f
        end
        value
    end

    def lock_file( file, timeout )

        raise ArgumentError, "you have not specified a filename to use as a lock" unless file
        timeout = validate_integer( timeout, 1, 60, "lock timeout" )
        @lock    = nil
        begin
            Timeout::timeout( timeout ) {
                @lock = File.open( file, File::RDWR | File::CREAT , 0644 ) 
                @lock.flock( File::LOCK_EX ) 
            }
        rescue Timeout::Error => e
            verb "lock_file: exceeded timeout %d secs, trying to acquire lock #{e.message}" % [ timeout ]
            raise Timeout::Error, "exceeded timeout to acquire the lock" 
        end 
        @lock

    end

    
    LESS     = 0
    GREATER  = 1
    RANGE    = 2
    EQUALS   = 3

    #########################################################################
    #         Thresholding
    #########################################################################

    def get_threshold( threshold )

        verb( "get_threshold: threshold=>#{threshold}" )
        result = { :compare => :GREATER }
        if threshold.is_a?( Integer ) 
            result[:threshold] = threshold.to_f
            return result
        end
        if threshold.is_a?( Float   )
            result[:threshold] = threshold
            return result
        end
        if threshold =~ /^:([0-9]+)$/
            result[:compare]   = :LESS
            result[:threshold] = $1.to_f
        elsif threshold =~ /([0-9]+):([0-9]+)/
            result[:compare]           = :RANGE
            result[:min],result[:max]  = $1, $2
        elsif threshold =~ /:([0-9]+):/
            result[:compare]   = :EQUALS
            result[:threshold] = $1.to_f
        else
            result[:threshold] = threshold.to_f 
            result[:compare]   = :GREATER
        end
        verb( "get_threshold: result=>#{result}" )
        result
    
    end

    def get_threshold_result( name, comparason, value, status )
        name ||= ''
        verb "get_threshold_result: name=>#{name} #{comparason} value=>#{value} value type=>#{value.class} threshold=>#{comparason[:threshold].class}"
        return { :status => status, :message => "#{name} (#{value}<#{comparason[:threshold]})" } if comparason[:compare] == :LESS    and value < comparason[:threshold]
        return { :status => status, :message => "#{name} (#{value}>#{comparason[:threshold]})" } if comparason[:compare] == :GREATER and value > comparason[:threshold]
        return { :status => status, :message => "#{name} (#{value}!=#{comparason[:threshold]})" } if comparason[:compare] == :EQUALS  and value != comparason[:threshold]
        return { :status => status, :message => "#{name} (#{value}<#{comparason[:min]}>#{comparason[:max]})" } if comparason[:compare] == :RANGE   and value > comparason[:min] and value < comparason[:max]
        :OK
    end

    def threshold( name, value, warning, critical, &block )

        verb "threshold: name=>#{name}, value=>#{value}, warning=>#{warning}, critical=>#{critical}"
        raise ArgumentError, "you must specify the name of the threshold"                  unless name
        raise ArgumentError, "you need to specify a value to check the threshold against"  unless value 

        the_value        = to_float( value )
        threshold_status = { :status => :OK, :message => nil }

        # the warnings and critical can be passed as a string or value
        threshold_status = get_threshold_result( name, get_threshold( warning  ), the_value, :WARNING  ) if warning
        threshold_status = get_threshold_result( name, get_threshold( critical ), the_value, :CRITICAL ) if critical

        # if the result is not OK and we have a block we yield the result, if the status is no ok and 
        # we don't have a block we set the instance variable @status
        unless threshold_status == :OK
            yield threshold_status[:status], threshold_status[:message] if block_given?
            @status = threshold_status[:status] if @status != :CRITICAL 
        end

    end

    def nagios_exit( level )
        @@codes[level] || 3
    end


    #########################################################################
    #         Statistcs methods
    #########################################################################

    def has_statistics( filename )
        return false unless File.exist?( filename )
        return false unless File.readable?( filename )
        return false unless File.file?( filename )
        return true
    end

    def load_stats( file )
        verb "load_stats: loading the statistis file #{file}"
        return nil unless has_statistics( file )
        return @statistics[:file] if @statistics and @statistics[:file]
        begin
            @statistics         = {} unless @statistics
            @statistics[:file]  = YAML.load_file( file )
            @statistics[:file]
        rescue Exception => e 
            raise Exception, "load_stats: unable to read in statistics file, error: #{e.message}"
        end
    end

    def write_stats( file, stats )
        # step, lets validate the statistics
        stats.each do |k,value| 
            validate_statistic value
            value[:stamp] = Time.now.to_i
        end
        if has_statistics( file )
            former = load_stats( file )
            former.merge!( stats )
            stats  = former
        end
        File.open( file, "w" ).puts( stats.to_yaml )
    end

    def nagios_exit( level )
        @@codes[level] || 3
    end

    def set_threshold( current, switch )

    end

    def validate_filename( filename, name )

        raise ArgumentError, "you have not specified a filename #{name}"    unless filename
        raise ArgumentError, "the file #{filename} does not exist"          unless File.exist?( filename )
        raise ArgumentError, "the file #{filename} is not a regular file"   unless File.file?( filename )
        raise ArgumentError, "the file #{filename} is not readable"         unless File.readable?( filename )
        filename

    end

    # validates a string against a user defined regex
    def validate_string( data, regex, name ) 
        verb( "validate_string: data: #{data} name: #{name}")
        raise ArgumentError, "validate_string: you need to define a regex"    unless regex
        raise ArgumentError, "validate_string: you need to define a name"     unless name
        raise ArgumentError, "#{name} is invalid, no value has been assigned" unless data 
        raise ArgumentError, "validate_string: the value passed for #{name} is not a string" unless data.is_a?( String )
        return data if data =~ regex
        raise ArgumentError, "#{name} has an invalid value, please check" 
    end
   
    def validate_regex( regex, name = nil )
        message = ( name ) ? "you need to specify #{name} option" : "invalid regex supplied"
        raise ArgumentError, message unless regex
        regex
    end
 
    def validate_threshold( value, message )
        raise ArgumentError, "validate_threshold: you need to define a message for the threshold" unless message
        raise ArgumentError, message unless value
        raise ArgumentError, "#{message} #{value} is not a valid threshold" unless value =~ /^(:[0-9]+|[0-9]+|[0-9]+:[0-9]+)$/
        value
    end

    def validate_username( username )
        raise ArgumentError, "you have not specified a username to connect with" unless username
        raise ArgumentError, "the username specified is invalid, please check"   unless username =~ /#{@@regexes[:username]}/
        return username
    end

    def validate_password( password) 
        raise ArgumentError, "you have not specified a password to connect with" unless password
        raise ArgumentError, "the password specified is invalid, please check"   unless password =~ /#{@@regexes[:password]}/
        return password
    end

    # @TODO needs to be added
    def validate_hostname( hostname )
        raise ArgumentError, "you must specify a hostname" unless hostname 
        hostname
    end

    def validate_integer( value, min, max, name, int = 0 )
        raise ArgumentError, "you must specify a name for the value"      unless name
        raise ArgumentError, "you have not specified a value for #{name}" unless value
        verb( "validate_integer: value: #{value} name: #{name} min: #{min} max: #{max} " )
        unless value.is_a?( Integer) 
            raise ArgumentError, "#{name} is not a integer" unless value =~ /^[0-9]+$/  
        end
        value = value.to_i if value.is_a?( String )
        raise ArgumentError, "#{name} must be greater than #{min}" if value < min 
        raise ArgumentError, "#{name} must be less than #{max}"    if value > max   
        value
    end

    def validate_timeout( value, min, max ) 
        begin 
            verb( "validate_timeout: value: #{value} min: #{min} max: #{max} ")
            timeout = validate_integer( value, min, max, "timeout" )
        rescue Exception => e
            raise ArgumentError, "the timeout specified is invalid, please check error: #{e.message}"
        end
    end

    def validate_port( port )
        validate_integer( port, 1, 65535, "port" ) 
    end

    def quit( level, message )
        
        exit_code = @@codes[level] || -1
        usage "invalid exit code #{exit_code} specified" unless exit_code >= 0
        puts "%s: %s" % [ level, message ]
        exit exit_code

    end

end
