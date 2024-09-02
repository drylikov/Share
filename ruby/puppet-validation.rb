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


$LOAD_PATH << File.dirname(__FILE__)
require 'optparse'
require 'modules/logging.rb'
require 'modules/git.rb'
require 'modules/utils.rb'
require 'modules/puppet.rb'

Version     = '0.0.1'
Prog        = "puppet-validation.rb"

$lint_opts  = ""
# some shortcuts
l = Log 
p = Puppet
l.set_level( 'die' )
p.setup

class PuppetValidator

    @config = nil

    def initialize( options )

        @config = options
    
    end

    # desc: we need to check we have all the requirements 
    def check_prereqs

        begin
            
            Log.debug( "checking the requirements first" )
            Log.debug( "our we in the correct git branch, current branch %s, required %s" % [ Git.get_current_branch, @config[:branch] ] )
            if @config[:branch] and Git.is_branch( @config[:branch] ) == false
                Log.debug "were not in the correct git branch, checking out %s" % @config[:branch]
                Git.checkout_branch( @config[:branch] ) 
            end
            Log.debug( "we are in the correct git branch %s" % [ @config[:branch] ] )

            # looking for puppet-lint if required
            if @config[:lint] 
                Log.debug( "looking for puppet-lint installation" )
            end

        rescue Exception => e
            
            # lets throw an error and quit for now
            Log.error "unable to satifiy prerequesites #{e.message} #{e.backtrace.inspect}"
            raise "unable to satifiy prerequesites "

        end

    end

    def validate 

        # lets check for the requirements
        check_prereqs

        changes = nil
        template_changes = nil
        # are we checking all the manifests?

        if @config[:last_commit]

            Log.die "the commit id does not exist, please check" unless Git.has_commit( @config[:last_commit] )
            # get all the files that have changed since this commit 
            changes = Git.files_changed( @config[:last_commit], @config[:to_commit] ).select{ |x| x =~ /^.*\.pp$/ } 
            template_changes = Git.files_changed( @config[:last_commit], @config[:to_commit] ).select{ |x| x =~ /^.*\.perb/ } 
            Log.info "there are no changes to any manifests between theses commits" if changes.empty?
            Log.info "kicking off validation, %d manifests %d templates between %s and %s" % [ template_changes.count, changes.count, @config[:last_commit], @config[:to_commit ] ] 

        else

            Log.info "kicking off validation of all puppet manifest in %s directory" % [ @config[:modules ] ]

        end

        # lets perform the validate of the manifests
        status = validate_manifests( changes )
        generate_summary( status )

    end

    def generate_summary( status )

        total_passed = status.reject{ |k,v| k.is_a?(TrueClass) }
        total_failed = status.reject{ |k,v| k.is_a?(String) }
        total = total_passed.count + total_failed.count
        50.times {|i| print "-" } 
        printf "\nsummary, total manifests:%d passed:%d failed:%d\n" % [ total, total_passed.count, total_failed.count ]
        50.times {|i| print "-" } 
        print "\n"

    end 

    def validate_templates( files ) 

        templates = files || Utils.all_files( @config[:modules], "^.*\.erb" )
        Log.info "found %d templates in modules directory %s, validating them now" % [ templates.count, @config[:modules ] ]
        status = {}
        templates.each do |template| 

            status["#{template}"] = true
            begin
                Puppet.validate_template( template )                    
            rescue Exception => e
                status[ template ] = e.message
            end
            unless @config[:summary_only]
                print " %-10s %s\n" % [ ( status[ template ].is_a?(TrueClass) ) ? "[passed]" : "[failed]", template ] 
            end
            unless status[ template ].is_a?(TrueClass)
                print "validation error:\n"
                print "%s\n" % [ status[ template ] ]
            end

        end
        status

    end

    def validate_manifests( files )

        
        checks_files = files || Utils.all_files( @config[:modules], "^.*\.pp$" ) 
        Log.info "found %s manifests in %s" % [ checks_files.size, @config[:modules] ]
        status = {}
        checks_files.sort.each do |manifest| 

            status["#{manifest}"] = true
            begin
                Puppet.validate_manifest( manifest )                    
            rescue Exception => e
                status[ manifest ] = e.message
            end
            unless @config[:summary_only]
                print " %-10s %s\n" % [ ( status[ manifest ].is_a?(TrueClass) ) ? "[passed]" : "[failed]", manifest ] 
            end
            unless status[ manifest ].is_a?(TrueClass)
                print "validation error:\n"
                print "%s\n" % [ status[ manifest ] ]
            end

        end

        return status

    end

end

# lets process the command line options
arguments = {
    :banner      => "Usage: %s [options] -M <path to puppet modules>" % [ Prog ],
    :version     => Version,
    :options     => [
        [ :modules,      nil,    true,  "-M", "--modules path", "the path to the puppet modules" ],
        [ :branch,       nil,    false, "-B", "--branch branch_name", "the git branch we should be in" ],
        [ :report,       nil,    false, "-R", "--report emails", "send a summary report to the comma seperated email list"],
        [ :last_commit,  nil,    false, "-C", "--commit commit id", "validate all files changed since this commit" ],
        [ :to_commit,    "HEAD", false, "-T", "--to-commit commit id", "the default to commit is from commit id to HEAD" ],
        [ :lint,         false,  false, "-L", "--lint", "validate all files changed since this commit" ],
        [ :lint_opts,    nil,    false, "-O", "--lint_opts options", "a list of options passed to the puppet-lint validator" ],
        [ :lint_dir,     nil,    false, "-D", "--lint_dir path", "the path to the installation of puppet-lint" ],
        [ :summary_only, false,  false, "-S", "--summary_only", "give a summary only of the modules validation" ],
        [ :logging,     "info",  false, "-l", "--logging [level]", "set the logging level - %s " % [ l.get_levels ] ]
    ]
} 

begin
    options = Utils.get_options( arguments )
    l.set_level( options[:logging] )
rescue => e
    Log.die "#{e.message}"
    exit 1
end

unless options[:modules]
    Log.die "you need to specify a path to the puppet modules" 
    optparse
end

valid = PuppetValidator::new( options )
begin
    valid.validate   
rescue
    Log.die "an error occured trying to validate the manifests, please check, #{$!}"
end
