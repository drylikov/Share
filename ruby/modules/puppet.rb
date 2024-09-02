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

module Puppet 

	@puppet  = nil
    @erb     = nil
	@version = nil

    def Puppet.setup

    	Log.debug "initializing the puppet module"
    	@puppet = %x[ which puppet ].chomp
    	unless ( @puppet )  
    		Log.error "unable to find the puppetd binary in path" 
    		return
    	end    	
    	@version = %x( #@puppet --version 2>/dev/null ).chomp
    	Log.debug "puppet binary found at %s version %s" % [ @puppet, @version ]

        @erb = %x[ which erb ].chomp
        unless @erb
            Log.error "unable to find the erb binary in path, please check"
            return    
        end

    end

	def Puppet.get_puppet_version

		@version

	end

    def Puppet.validate_template( template )

        raise "wasn't able to find the erb binary in the current path" unless @erb
        raise "#{template} doesn't appear to be a file" unless File.file?
        out = %x[ #@erb -x -T '-' #{template} | ruby -c ]
        raise "parsing error in template #{template}, error #{out}" unless $? == 0

    end

	def Puppet.validate_manifest( manifest )

		raise "we were unable to find the puppetd binary in the path" unless @puppet		
		out = %x( #@puppet parser --ignoreimport validate #{manifest} 2>/dev/null ).strip
		raise "parsing error in manifest #{manifest}, error #{out}" unless $? == 0

	end

end