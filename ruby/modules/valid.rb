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

module Validator

	Regex_ipaddress = "^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$"
	Regex_hostname  = "^[a-z\-]*[0-9]{3}-dc[13]$"

	def is_hostname( name )
    	if ( name =~ /#{Regex_hostname}/i )
    	    return name
    	else
    	    die "the hostname #{name} is invalid, example: test301-dc[13]"
    	end
    end
	
	def is_ipaddress( address ) 
		if ( address =~ /#{Regex_ipaddress}/ )
		    return address
		end
		die "the ip address #{address} seems to be invalid, please check"
    end


end