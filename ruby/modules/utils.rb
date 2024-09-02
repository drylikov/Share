#!/usr/bin/ruby
#
#   Author: Rohith
#   Date: 2013-04-24 13:57:18 +0100 (Wed, 24 Apr 2013)
#  $LastChangedBy$
#  $LastChangedDate$
#  $Revision$
#  $URL$
#  $Id$
#
#  vim:ts=4:sw=4:et

module Utils

    def Utils.all_files( path, filter = ".*" )
        Dir.glob( "#{path}/**/*" ).select{ |x| x =~ /#{filter}/ and File.directory?( x ) == false }
    end

    def Utils.get_options( options )

        args = {}
        raise "no arguments have been assigned" unless options[:options]
        optparse = OptionParser.new do|opts|
            opts.banner = options[:banner]
            opts.separator ""
            options[:options].each do |opt|
                args[ opt[0] ] = opt[ 1 ]
                if opt[4] =~ /^--[a-zA-Z\-_]* \[?\w\]?/
                    opts.on( opt[3], opt[4], opt[5] ) do |arg|
                        args[ opt[0] ] = arg
                    end
                else
                    opts.on( opt[3], opt[4], opt[5] ) do 
                        args[ opt[0] ] = true
                    end
                end
            end
        end
        optparse.parse!

        # make sure we have all the required parameters
        options[:options].each do |x|
            if x[2].is_a?( TrueClass ) and args[ x[0] ] == nil
                print "\n%s\n" % [ optparse ]
                Log.die "invalid, parameter %s has not been defined" % [ x[4] ] unless args[ x[0] ]
                raise
            end
        end

        return args
      
    end  

end
