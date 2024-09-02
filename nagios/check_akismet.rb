#!/usr/bin/ruby 
#
#   Author: Rohith
#   Date: 2013-08-13 10:10:32 +0100 (Tue, 13 Aug 2013)
#
#  vim:ts=4:sw=4:et
#


$:.unshift File.join(File.dirname(__FILE__),'.','rubylibs')
require 'rubygems' if RUBY_VERSION < '1.9.0'
begin
    gem "rest-client"
rescue Gem::LoadError
    puts "Error, the plugin requires the rest-client gem installed"
end
require 'pp'
require 'optparse'
require 'logging'
require 'nagiosutils'

include Logging
include NagiosUtils

Meta = {
    :prog     => "#{__FILE__}",
    :author   => "Rohith",
    :email    => "gambol99@gmail.com",
    :date     => "2013-08-14 12:12:32 +0100",
    :version  => "0.0.1"
}

options = { 
    :hostname     => 'rest.akismet.com',
    :protocol     => 'http',
    :token        => nil,
    :api_version  => '1.1',
    :comment_url  => 'comment-check',
    :comment      => { 
        :blog                 => nil,
        :user_ip              => nil,
        :user_agent           => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/29.0.1547.76 Safari/537.36',
        :comment_type         => 'comment',
        :comment_author       => 'Nagios Test',
        :comment_author_email => nil,
        :comment_content      => 'this is a test'
    },      
    :timeout      => 10,
    :verbose      => false,
}

# lets get the options
Parser = OptionParser::new do |opts|
    opts.on( "-H", "--host hostname",      "the hostname | ip address comment checking service (defaults to #{options[:hostname]})" )   { |arg| options[:hostname]     = arg    }
    opts.on( "-t", "--timeout timeout",    "the critical threshold in seconds to wait until timing out" )                               { |arg| options[:timeout]      = arg    }
    opts.on( "-T", "--token token",        "the token used as verification of the Akismet comment service" )                            { |arg| options[:timeout]      = arg    }
    opts.on( "-c", "--comment comment",    "the comment you wish verify with the Akismet service" )                                     { |arg| options[:comment][:comment_content]      = arg }
    opts.on( "--comment_ip ipaddress",     "the comment ip address you wish to accompany with the comment" )                            { |arg| options[:comment][:user_ip]              = arg }
    opts.on( "--comment_author author",    "the comment author you wish to accompany with the comment" )                                { |arg| options[:comment][:comment_author]       = arg }
    opts.on( "--comment_email email",      "the comment email address you wush to use" )                                                { |arg| options[:comment][:comment_author_email] = arg }
    opts.on( "--comment_type type",        "the comment content type you to use" )                                                      { |arg| options[:comment][:comment_type]         = arg }
    opts.on( "-v", "--verbose",            "switch on verbose logging" )                                                                { |arg| options[:verbose]      = true   }
end
Parser.parse!

# lets validate the arguments
begin
    
    @verbose = options[:verbose] if options[:verbose]
    options[:hostname] = validate_hostname( options[:hostname] )
    options[:timeout]  = validate_timeout( options[:timeout], 5, 60 )
    options[:token]    = validate_string( options[:token], /^[0-9a-z]{12}$/, 'akismet token' )
    options[:comment][:comment_content]         = validate_string( options[:comment][:comment_content], /^[a-zA-Z0-9 ]+$/, 'comment content' )
    options[:comment][:comment_author]          = validate_string( options[:comment][:comment_author], /^[a-zA-Z0-9 ]+$/, 'comment author' )
    options[:comment][:comment_author_email]    = validate_string( options[:comment][:comment_author_email], //, 'comment author email' )
    options[:comment][:comment_type]            = validate_string( options[:comment][:comment_type], /^(blank|comment|trackback|pingback)$/, 'comment type' )

rescue ArgumentError => e 
    verb     "invalid arguments, exitting the check"
    usage e 
rescue Exception     => e
    quit :UNKNOWN, "internal error thrown #{e.message}"
end

start_time    = Time.now
begin

    verb "hostname: %s token: %s comment: %s "  % [ options[:hostname], options[:token], options[:comment][:comment_content] ]
    akismet_url = '%s://%s.%s/%s/%s' % [ options[:protocol], options[:token], options[:hostname], options[:api_version], options[:comment_url] ]
    verb "akismet rest url: %s " % [ akismet_url ]
    verb "attempting a request to akisnet service on url: %s comment: %s" % [ akismet_url, options[:comment][:comment_content] ]
    client = nil
    Timeout::timeout( options[:timeout] ) {
        client = RestClient.post akismet_url, options[:comment]
    }
    verb "successfully make rest request to akismet comment checking service, code: %s body: %s" % [ client.code, client.body ]
    verb "response from akismet service: %s" % client
    response_time = ( Time.now - start_time ) * 1000 
    quit :OK, "Akismet Comment Service, response_time: #{response_time}ms | 'response_time'=#{response_time};;"

rescue Errno::ECONNREFUSED => e
    quit :CRITICAL, "connection to refused to akismet service"
rescue Timeout::Error => e
    quit :CRITICAL, "check timed out connecting to activemq, unable to pull activemq queue statistics"
rescue SystemExit => e
    exit e.status 
rescue Exception => e 
    quit :CRITICAL, "internal error: " << e.message
end



