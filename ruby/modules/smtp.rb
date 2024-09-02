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

require "net/smtp"

module SMTP

    @smtp_hostname  = localhost
    @smtp_port      = 25

    def SMTP.send_email( from, to, message )

        begin
        
            Log.info( "sending email from:#{from} to:#{to}")
            Net::SMTP.start( @smtp_hostname ) do |smtp|
                smtp.send_message message, from, to
            end

        rescue Exception => e
            
            Log.error "unable to send email, error #{e.message}"
            raise

        end

    end

end
