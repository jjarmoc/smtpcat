#!/usr/bin/ruby -w
###################
# smtpcat.rb v1.0 #
# 11/20/2009      #
# Jeff Jarmoc     #
# Jeff@Jarmoc.com #
###################

require 'rubygems'
require 'tmail'
require 'optparse'
require 'base64'
require 'digest/md5'

class Smtp_Session
attr_accessor :rawdata, :msg, :commands, :cmds

def saveattachments(dir)
  # Write attachment, calculate and print MD5
    msg.attachments.each { |attach|
      outfile = dir + attach.original_filename
      File.open(outfile,"w+") {|local_file| 
        local_file << attach.gets(nil)
      }
      print "+ Wrote: #{outfile}\n"
 	    print "+ Size:  #{File.size(outfile)} bytes\n"
      print "+ MD5:   #{Digest::MD5.hexdigest(File.read(outfile))} \n\n"
    }	
end

def showmsg()
  puts "-----Displaying Message Body"
  print "Received:\t#{msg.date.to_s}\n"
  print "From:    \t#{msg.from.to_s}\n"
  print "To:      \t#{msg.to.to_s}\n"
  if (msg.cc)
    print "CC:      \t#{msg.cc.to_s}\n"
  end
  if (msg.bcc)  
    print "BCC:     \t#{msg.bcc.to_s}"
  end
  print "Subject: \t#{msg.subject.to_s}\n"
  print "\n"
  print msg.body()
end

def cmd?(cmd)
	searchcmd = Regexp.new(cmd)
	@commands.keys.each { |k|
		if ( k =~ searchcmd)
	 		return true
		end
	}
false	
end

def getcmd(cmd)  
           searchcmd = Regexp.new(cmd)
           @commands.each_pair { |key, val| 
                                 if ( key =~ searchcmd )
					                          return key, val	  
                                 end
                            }
end

def parseesmtp(data)
       line = data.slice!(0)
       if (line =~ /\AEHLO/i)
         @currcmd = line  
        # We're talking ESMTP, so grab other commands the server advertises, and add them to our array of valid commands
        response = data.slice!(1..(1..data.length).select{|x|
         data[x] !~ /\A[0-9]{3}/}.first - 1).to_s
          # puts "***" 
          # pp response
          response.each { |resp| 
            @commands[@currcmd] ||= []
            @commands[@currcmd] << resp
            @cmds << resp.chomp.gsub(/\A[0-9]{3}./,"").gsub(/ .*/,"")
            }          
        end
response
end

def initialize(data)
      @rawdata = data.clone
      @commands = Hash.new
      # Here we have standard SMTP commands, plus EHLO for ESMTP
      # If EHLO is found, we'll learn other supported ESMTP commands.
      @cmds = ["HELO", "EHLO", "RCPT", "MAIL", "ETRN", "VRFY", "SIZE", "DATA", "QUIT", "EXPN"]
      # Pull out the message body from between the servers '354 START MAIL INPUT' response and the client's '.' command
      # Make it a TMail Object

      @msg = TMail::Mail.parse(data.slice!(
        (0..data.length).select{|a| data[a] =~ /\A354.*/}.first + 1 ..
        (0..data.length).select{ |a| data[a] =~ /\A\./}.first - 1).to_s)
      
      @commands[""] ||= []
      @commands[""] << data.slice!(0)
      
      if (! data.include?(/\AEHLO/))
        #Session uses ESMTP, parse out servers advertised commands
        self.parseesmtp(data)
      end
      
      while (! data.empty?)
       #Parse remaining data, CMD / (possibly multiple) response.
        line = data.slice!(0)  # Parse next line
        if (@cmds.include?(line.gsub(/ .*/,"").chomp)) # LINE is a command          
            @currcmd = line        
        else  #LINE is not a command, so it's a response to the previous command. 
          @commands[@currcmd] ||= []
          @commands[@currcmd] << line
       end
end
 
end


# BEGIN MAIN

# first, process arguments
options = {}
optparse = OptionParser.new do|opts|
	opts.banner = "Usage: smtpcat.rb [option] filename(s)"
	opts.separator "- Version 1.0 - 11/20/2009 - Jeff Jarmoc"
	opts.separator "\t"
	opts.separator "Specific options:"

	opts.on( '-h','-?','--help','Display this screen' ) do
		puts opts
		exit
	end

	options[:findcmds] = []
	opts.on('-c', '--commands CMD1,CMD2,CMD3', Array, "SMTP commands to Display") do |l|
		options[:findcmds] = l 
	end

	options[:b64dcmds] = []
	opts.on('-d', '--decode CMD1,CMD2,CMD3', Array, "SMTP commands to Base64 Decode") do |l|
		options[:b64dcmds] = l
	end
  
  options[:showmsg] = true
	opts.on('-n', '--nomsg', "Hide Message Body") do |f|
	    options[:showmsg] = false
	end

	options[:outdir] = false
	opts.on('-o', '--outdir [DIR]', "Output file attachments and show MD5", "  optionally to DIR, Current dir by default") do |f|
		if (f.include?("/"))  #Make sure the next part is a dir, and not an input file
			options[:outdir]= f || ""
		else
		   ARGV = f	# If it's not a dir, it's a file.. re-add it to ARGV
		   options[:outdir] = "" # and use CWD
		end
	end

	opts.separator ""
end
optparse.parse!

#get input file name, with destructions Option Parsing (!) that's all we have left.
if (ARGV.empty?)
	print "ERROR: No Input File specified!\n"
	print "Try '-h' for help\n"
   	exit
end

ARGV.each { |infile|  

print "**** Processing SMTP stream from #{infile}\n"

begin # Read infile into array
file = File.new(infile, "r")
    inputdata = file.readlines()
file.close
rescue => err
      puts "Exception: #{err}"
      err
end

session = Smtp_Session.new(inputdata) # Make an SMTP session object from our data.

# Display requested commands
options[:findcmds].each { |c|		
	print "--== Displaying Command: #{c}\n"
	if (session.cmd?(c)) 
		key, val = session.getcmd(c)
		print "C->S #{key}"
		val.each { |v|
			if (v =~ /\A[0-9]{3}/)
				print "C<-S #{v}"
			else
				print "C->S #{v}"
			end
		}
	else
	 	print "--== Command Not found! ==--\n"
	end
	puts ""
	}

# Display requested commands, B64 decoding as we go..
options[:b64dcmds].each { |c|
	print "--== Decoding Command: #{c}\n"
		if (session.cmd?(c)) 
			key, val = session.getcmd(c)
			print "C->S #{key}"
			val.each { |v|
				if (v =~ /\A[0-9]{3} /)
				  if (v !~ /\A3[0-9]{2} /)
				    print "C<-S #{v}"
					else
					  print "C<-S #{v.slice!(0..3)}#{Base64.decode64(v)}\n"
				  end
				else
					print "C->S #{Base64.decode64(v)}\n"
				end
			}
		else
		 	print "--== Command Not found! ==--\n"
		end
		puts ""
	}

#Show message body if requested
if (options[:showmsg]) 
  session.showmsg()
end

#Output file, if requested.
if (options[:outdir])
  session.saveattachments(options[:outdir])
end
}
end


