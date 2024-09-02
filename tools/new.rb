#!/usr/bin/ruby

require 'yaml'
require 'pp'
require 'optparse'
require 'erb'

Info = {
	:author  => "Rohith",
	:email   => "gambol99@gmail.com",
  	:version => "0.0.1",
        :prog    => __FILE__
}

class ConfigurationError < StandardError
end

module Utils

    module Path

        def which(cmd)
            exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
            ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
                exts.each { |ext|
                    exe = File.join(path, "#{cmd}#{ext}")
                    return exe if File.executable? exe
                }
           end
           return nil
        end

    end

    module Config

        def has_configuration( config )
             raise ConfigurationError, "invalid configuration specified" unless config or config.empty? == false
             found = false
             config.each do |file|
                  if File.exists?( file )
                      raise ConfigurationError, "configuration file #{file} is not a file"   unless File.file?( file )
                      raise ConfigurationError, "configuration file #{file} is not readable" unless File.readable?( file )
                      found = true
                  end
             end
             raise ConfigurationError, "unable to find any configuration files" unless found == true
        end

        def load( configs = [] ) 
             cfg = {}
             configs = [ configs ] unless configs.is_a?( Array )
             configs.each do |config|
                 if File.file?( config ) and File.readable?( config )
                     config = YAML::load_file( config )
                     cfg = ( cfg.empty? ) ? config :  config.merge( cfg )
                 end
             end
             raise ConfigurationError, "unable to read any configuration" if cfg.empty?
             cfg
        end

        def usage( config, msg = nil )
             puts config
             if msg
                 puts "\nerror: #{msg}\n"
                 exit 1
             end
             exit 0    
        end

    end

    module Headers

        class Binding

            def put( key, value )
                instance_variable_set( "@"+key.to_s, value )
            end

            def get_binding
                binding()
            end

        end

        def get_templates( config, suffix = nil, tpl = nil )

            # step: if we have no suffix, lets find the default header
            if suffix == false and tpl == false
                config[:headers].each { |header| return header if header[:id] == "default" }
                raise ArgumentError, "configuration does not have a default header to apply"
            elsif suffix and tpl == nil
                config[:headers].select { |item| item if /#{item[:suffix]}/ =~ suffix }
            elsif
                config[:headers].select { |item| item if tpl.include?( item[:id] ) }
            end

        end 

        def validate_headers( config )

            raise ArgumentError, "unable to find any headers in the configuration" unless config[:headers]
            valid_header_tags = [ :suffix, :id, :desc, :exec ] 
            valid_config_tags = [ :headers, :author, :alias ]
            valid_config = { :headers => [] }
            config.each do |tag,value|
                next unless valid_config_tags.include?( tag ) 
                if tag == :headers 
                    value.each do |item|
                        item.each do |key,value|
                            unless valid_header_tags.include?( key ) == false or value.length > 0 
                                puts "error, invalid tag in header template #{key}, skipping item"
                                next
                            end 
                        end
                        valid_config[:headers] << item
                    end
                else
                    valid_config[tag] = value
                end
             end 
             valid_config
        end

        def show_templates
            puts <<EOF
- :id: default  
  :suffix: sh
  :desc: Bash shell script
  :exec: bash
  :header: ! <%=exec%>
# 
# author: <%=author%>
# date:   <%=date%>
# file:   <%=path%>
   
EOF
           exit 0
       end

       def show_headers( config )
           puts "headers:\n"
           config[:headers].each do |h|
               puts "[header] %-10s extensions: %s" % [ h[:id], h[:suffix] ]
               puts "description : #{h[:desc]}"    if h[:desc]
               puts "comment     : #{h[:comment]}" if h[:comment]
               puts "header      : "
               puts h[:header]
               puts 
           end
           exit 0
      end

      def header( config, options, header ) 

          raise ConfigurationError, "no configuration passed to create file" unless config
          raise ConfigurationError, "no header passed to create the file"    unless header

          include Utils::Path
          # step: lets generate the dynamic tags
          data = Binding::new
          data.put( :date, Time.now )
          data.put( :author, config[:author] || '' )
          data.put( :filename, File.path( options[:filename] ) )
          data.put( :path, File.absolute_path( options[:filename] ) )
          content = nil
          if header.count == 1
              head = header.first
              data.put( :exec, which( head[:exec] ) || '' ) if head[:exec]
              content = ERB.new(head[:header]).result( data.get_binding ) 
          else
              raise ConfigurationError, "you seems to have #{header.count} headers the conflict" unless options[:merge] and options[:alias]
              


              
          end
         
          unless options[:test_only] 
              File.open( options[:filename], "w" ).puts( content ) 
          else
              puts content
          end

      end

    end

end

include Utils::Config
include Utils::Headers

options = {
    :config         => [ "#{ENV['HOME']}/.headers.yaml", "#{ENV['HOME']}/.new.yaml" ],
    :show_list      => false,
    :show_templates => false,
    :test_only      => false
}
parse = OptionParser::new do |o|
    o.banner = "Usage: %s -f <filename>" % [ Info[:prog] ]
    o.on( "-f", "--file filename",      "the filename of the new script you wish to create" ) { |arg|  options[:filename] = arg  }
    o.on( "-c", "--config filename",    "the path/filename of the config file" )              { |arg|  options[:config]   = arg  }
    o.on( "-H", "--merge headers",      "the header type to use in the new file" )            { |arg|  options[:merge]   = arg.split(',')  }
    o.on( "-T", "--templates",          "display the headers display exmaples" )              {        options[:show_templates]  = true }
    o.on( "-t", "--test",               "run in test mode, display header only" )             {        options[:test_only]  = true }
    o.on( "-l", "--list",               "list the headers available" )                        {        options[:show_list]  = true }
    o.on( "-v", "--version",            "diplsy the version information" ) do
        puts "\n%s - written by %s (%s) version:%s" % [ Info[:prog], Info[:author], Info[:email], Info[:version] ]
        exit 0
    end 
end
parse.parse!

# step: lets do some error checking on the aruguments
begin
    usage parse, "you haven't specified a configuration to read in" unless options[:config]
    if options[:show_list] and options[:show_templates]
        usage parse, "you haven't specified a filename to create"   unless options[:filename]
    end
    has_configuration( options[:config] ) 
rescue ConfigurationError => e
    usage parse, e.message    
end

# step: check if the filename already exists
if options[:filename] and File.file?( options[:filename] )
   print "[warning] the file #{options[:filename]} already exists, you sure you wish to continue? y/n "
   choice = ARGF.gets.chomp
   unless /^[Yy]$/ =~ choice
       puts "exitting ..."
       exit 0
   end
end

begin
    
    # step: read in and validate the configuration
    config = load( options[:config ] )
    config = validate_headers( config )

    # step: we have a config now - lets process any one off arguments
    show_headers( config ) if options[:show_list]
    show_templates         if options[:show_templates]
    
    suffix = File.extname( options[:filename] )

    header = get_templates( config, suffix )
    raise ConfigurationError, "unable to find header template which aligns with file: #{options[:filename]} suffix: #{suffix}" unless header.count > 0

    header( config, options, header )    

rescue ConfigurationError => e

    puts "configuration error => #{e.message}"
    exit 1

rescue SystemExit, Interrupt => e

    puts "exitting the app ... "
    exit 0

rescue Exception => e
    puts "error: an exception was thrown trying to complete task, error=>#{e.message}"
    exit 1  
end

