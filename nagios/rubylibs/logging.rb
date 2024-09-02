#!/usr/bin/ruby -w
#
#   Author: Rohith
#   Date: 2013-08-13 10:10:32 +0100 (Tue, 13 Aug 2013)
#  $LastChangedBy$
#  $LastChangedDate$
#  $Revision$
#  $URL$
#  $Id$
#
#  vim:ts=4:sw=4:et

module Logging

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

end