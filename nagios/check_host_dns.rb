#!/usr/bin/env ruby
# Author: Rohith
# Description: the checks makes sure we have an dns 
# Notes: needs to be rewritten to use the naguis utils instead

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-plugin/check/cli'

Defaults = {
  :domains       => nil,
  :domain_regex  => "^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$"
}

class DNS < Sensu::Plugin::Check::CLI

  option :hostname,
    :short       => "-H hostname",
    :long        => "--host hostname",
    :description => "the hostname you wish to check dns against",
    :required    => true
    
  option :domains,
    :short       => "-d domains",
    :long        => "--domains domains",
    :description => "a comma seperated list of domain names",
    :required    => true,
    :default     => Defaults[:domains]

  option :ptr,
    :short       => "-r",
    :long        => "--with-ptr",
    :description => "make sure the we have a reverse ip (PTR) record as well",
    :default     => false

  option :verbose,
    :short       => "-v",
    :long        => "--verbose level",
    :description => "enable verbose output for this check",
    :proc        => proc {|p| p.to_i },
    :default     => 0

  option :required,
    :short       => "-R required",
    :long        => "--required required",
    :description => "specifies wheather you need it to be in all or any of the domains list",
    :default     => "any"

  def run
      usage "invalid required type, either all or any" unless [ "all", "any" ].include?( config[:required] )

      domains_list = []
      # lets validate the inputs, namely the domains list  
      config[:domains].split(",").each do |domain|
        usage "the domain name #{domain} is invalid" unless domain =~ /^[a-zA-Z0-9\.]+\.[a-zA-Z]{2,}$/
        domains_list << domain
      end
      domains_count = config[:domains].split(",").size;
      verbose "checking for hostname #{config[:hostname]} in domains #{domains_list.join(',')}"

      resolved = {}
      # lets perform the check now
      domains_list.each do |domain|
        fqdn = "#{config[:hostname]}.#{domain}"
        resolved[domain] = false
        verbose "checking for dns resolution of #{fqdn}"
        result = %x(host #{fqdn} >/dev/null 2>&1)
        resolved[domain] = true if $? == 0
      end
      
      failed = resolved.select { |fqdn,resolve| resolve == false }
      passed = resolved.select { |fqdn,resolve| resolve == true  }

      # did we need to pass all the resolves?
      if config[:required] == "all" and failed.size > 0 
        critical "failed to resolve dns for %s" % [ failed.select{ |k,v| k }.join(",") ] 
      end      

      # ok, did we pass some of them?
      critical "failed to resolve hostname #{config[:hostname]} in domain/s #{config[:domains]}" if passed.size <=0 
      ok       "hostname #{config[:hostname]} resolved in #{config[:domains]} domain" if domains_count == 1
      if passed.size > 0 and failed.size > 0
        ok "#{config[:hostname]} resolved in %s, but not %s" % [ passed.map{|k,v| k }.join(','), failed.map { |k,v| k }.join(",") ] 
      end
      # ok, we passed everything 
      ok "#{config[:hostname]} passed any domains #{config[:domains]}"

  end

  def usage( message = nil )

      print "%s\n"        % [ opt_parser ] 
      print "error: %s\n" % [ message ] if message
      exit 0 

  end

  def verbose( message = nil )

    puts "verb: %s\n" % [ message ] if config[:verbose] == 1 and message

  end

end
