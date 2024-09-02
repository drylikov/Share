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

class Level 

	@level = 0
	@timestamped = false

	def set_level( level )
		@level = level
	end

	def get_level
		return @level
	end

	def set_timestamp( flag )
		@timestamped = flag
	end

	def is_stamp
		return @timestamped
	end

end

# description: a generic module used for logging 
module Log

	@level   = Level::new
	@levels  = {
		"die"   => 0,
		"info"	=> 1,
		"warn"  => 2,
		"error" => 3,
		"debug" => 4,
 	}
	
	def Log.log( level, msg )
		tm = ""
		if @level.is_stamp
			time = Time.new
			tm   = time.strftime("%H:%M:%S")
		end 
		printf " %-7s %s : %s\n" % [ "[#{level}]", tm, msg ] if  @levels[level] <= @level.get_level
	end

	def Log.die( msg )
		log( "die", msg )
		exit 1
	end

	def Log.warn( msg )
		log( "warn", msg )
	end

	def Log.info( msg )
		log( "info", msg )
	end

	def Log.error( msg )
		log( "error", msg )
	end

	def Log.debug( msg )
		log( "debug", msg )
	end

	def Log.set_level( level )
		if @levels.has_key?( level ) 
			@level.set_level( @levels[ level ] )
		end
	end

	def Log.get_levels
		@levels.keys.join( ',' )
	end

	def Log.stamp( flag )
		@level.set_timestamp( flag )
	end

	def get_level
		return @level.get_level		
	end

end