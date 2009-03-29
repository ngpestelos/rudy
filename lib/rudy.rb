


require 'digest/md5'
require 'stringio'
require 'ostruct'
require 'yaml'
require 'socket'
require 'timeout'
require 'tempfile'

require 'rush' #, Tom Sawyer

require 'storable'
require 'console'
require 'annoy'

require 'net/ssh'
require 'net/scp'
require 'net/ssh/multi'
require 'net/ssh/gateway'


RUDY_HOME = File.join(File.dirname(__FILE__), '..') unless defined?(RUDY_HOME)
RUDY_LIB = File.join(File.dirname(__FILE__), '..', 'lib') unless defined?(RUDY_LIB)


module Rudy #:nodoc:
  RUDY_DOMAIN = "rudy_state" unless defined?(RUDY_DOMAIN)
  RUDY_DELIM  = '-' unless defined?(RUDY_DELIM)
  
  RUDY_CONFIG_DIR = File.join(ENV['HOME'] || ENV['USERPROFILE'], '.rudy') unless defined?(RUDY_CONFIG_DIR)
  RUDY_CONFIG_FILE = File.join(RUDY_CONFIG_DIR, 'config') unless defined?(RUDY_CONFIG_FILE)
  
  DEFAULT_REGION = 'us-east-1' unless defined?(DEFAULT_REGION)
  DEFAULT_ZONE = 'us-east-1b' unless defined?(DEFAULT_ZONE)
  DEFAULT_ENVIRONMENT = 'stage' unless defined?(DEFAULT_ENVIRONMENT)
  DEFAULT_ROLE = 'app' unless defined?(DEFAULT_ROLE)
  DEFAULT_POSITION = '01' unless defined?(DEFAULT_POSITION)
  
  DEFAULT_USER = 'rudy' unless defined?(DEFAULT_USER)
  
  SUPPORTED_SCM_NAMES = [:svn, :git] unless defined?(SUPPORTED_SCM_NAMES)
  
  ID_MAP = {
    :instance => 'i',
    :disk => 'disk',
    :backup => 'back',
    :volume => 'vol',
    :snapshot => 'snap',
    :kernel => 'aki',
    :image => 'ami',
    :ram => 'ari',
    :log => 'log',
    :reservation => 'r'
  }.freeze unless defined?(ID_MAP)
  
  @@quiet = false
  def Rudy.enable_quiet; @@quiet = true; end
  def Rudy.disable_quiet; @@quiet = false; end
  
  module VERSION #:nodoc:
    MAJOR = 0.freeze unless defined? MAJOR
    MINOR = 4.freeze unless defined? MINOR
    TINY  = 0.freeze unless defined? TINY
    def self.to_s
      [MAJOR, MINOR, TINY].join('.')
    end
    def self.to_f
      self.to_s.to_f
    end
  end
  
  # Determine if we're running directly on EC2 or
  # "some other machine". We do this by checking if
  # the file /etc/ec2/instance-id exists. This
  # file is written by /etc/init.d/rudy-ec2-startup. 
  # NOTE: Is there a way to know definitively that this is EC2?
  # We could make a request to the metadata IP addresses. 
  def Rudy.in_situ?
    File.exists?('/etc/ec2/instance-id')
  end
  
  
  # Wait for something to happen. 
  # * +duration+ seconds to wait between tries (default: 2).
  # * +max+ maximum time to wait (default: 120). Throws an exception when exceeded.
  # * +logger+ IO object to print +dot+ to.
  # * +dot+ the character to print after each attempt (default: .). 
  # Set to nil or false to keep the waiter silent.
  # The block must return false while waiting. Once it returns true
  # the waiter will return true too.
  def Rudy.waiter(duration=2, max=120, logger=STDOUT, dot='.', &check)
    # TODO: Move to Drydock
    raise "The waiter needs a block!" unless check
    duration = 1 if duration < 1
    max = duration*2 if max < duration
    success = false
    begin
      success = Timeout::timeout(max) do
        while !check.call
          logger.print dot if dot && logger.respond_to?(:print)
          logger.flush if logger.respond_to?(:flush)
          sleep duration
        end
      end
    rescue Timeout::Error => ex
      retry if Annoy.pose_question(" Keep waiting?\a ", /yes|y|ya|sure|you bet!/i, logger)
      raise ex # We won't get here unless the question fails
    end
    success
  end
  
  # Make a terminal bell chime
  def Rudy.bell(chimes=1, logger=STDERR)
    return if @@quiet
    chimed = chimes.to_i
    logger.print "\a"*chimes
    true # be like Rudy.bug()
  end
  
  # Have you seen that episode of The Cosby Show where Dizzy Gillespie... ah nevermind.
  def Rudy.bug(bugid, logger=STDERR)
    logger.puts "You have found a bug! If you want, you can email".color(:red)
    logger.puts 'rudy@solutious.com'.color(:red).bright << " about it. It's bug ##{bugid}.".color(:red)          
    logger.puts "Continuing...".color(:red)
    true # so we can string it together like: bug('1') && next if ...
  end

  # Is the given string +str+ an ID of type +identifier+? 
  # * +identifier+ is expected to be a key from ID_MAP
  # * +str+ is a string you're investigating
  def Rudy.is_id?(identifier, str)
    return false unless identifier && str && Rudy.known_type?(identifier)
    identifier &&= identifier.to_sym
    str &&= str.to_s.strip
    str.split('-').first == Rudy::ID_MAP[identifier].to_s
  end
  
  # Returns the object type associated to +str+ or nil if unknown. 
  # * +str+ is a string you're investigating
  def Rudy.id_type(str)
    return false unless str
    str &&= str.to_s.strip
    (Rudy::ID_MAP.detect { |n,v| v == str.split('-').first } || []).first
  end
  
  # Is the given +identifier+ a known type of object?
  def Rudy.known_type?(identifier)
    return false unless identifier
    identifier &&= identifier.to_s.to_sym
    Rudy::ID_MAP.has_key?(identifier)
  end
  
  # +msg+ The message to return as a banner
  # +size+ One of: :normal (default), :huge
  # +colour+ a valid 
  # Returns a string with styling applying
  def Rudy.make_banner(msg, size = :normal, colour = :black)
    return unless msg
    banners = {
      :huge => Rudy::Utils.without_indent(%Q(
      =======================================================
      =======================================================
      !!!!!!!!!   %s   !!!!!!!!!
      =======================================================
      =======================================================)),
      :normal => %Q(============  %s  ============)
    }
    size = :normal unless banners.has_key?(size)
    colour = :black unless Console.valid_colour?(colour)
    size, colour = size.to_sym, colour.to_sym
    sprintf(banners[size], msg).colour(colour).bgcolour(:white).bright
  end
  
  
end

require 'rudy/aws'
require 'rudy/utils'       # The
require 'rudy/config'      # order
require 'rudy/huxtable'    # of
require 'rudy/addresses'
require 'rudy/routines'    # require
require 'rudy/machines'    # statements
require 'rudy/manager'     # is
require 'rudy/backups'     # important.
require 'rudy/volumes'
require 'rudy/groups'
require 'rudy/disks'


# Require MetaData, Routines, and SCM classes
begin
  # TODO: Use autoload
  Dir.glob(File.join(RUDY_LIB, 'rudy', '{metadata,routines,scm}', "*.rb")).each do |path|
    require path
  end
rescue LoadError => ex
  puts "Error: #{ex.message}"
  exit 1
end



# ---
# TODO: Find a home for these poor guys:
# +++

def sh(command, chdir=false, verbose=false)
  prevdir = Dir.pwd
  Dir.chdir chdir if chdir
  puts command if verbose
  system(command)
  Dir.chdir prevdir if chdir
end


def ssh_command(host, keypair, user, command=false, printonly=false, verbose=false)
  #puts "CONNECTING TO #{host}..."
  cmd = "ssh -i #{keypair} #{user}@#{host} "
  cmd += " '#{command}'" if command
  puts cmd if verbose
  return cmd if printonly
  # backticks returns STDOUT
  # exec replaces current process (it's just like running ssh)
  # -- UPDATE -- Some problem with exec. "Operation not supported"
  # using system (http://www.mail-archive.com/mongrel-users@rubyforge.org/msg02018.html)
  (command) ? `#{cmd}` : Kernel.system(cmd)
end


def scp_command(host, keypair, user, paths, to_path, to_local=false, verbose=false, printonly=false)
  
  paths = [paths] unless paths.is_a?(Array)
  from_paths = ""
  if to_local
    paths.each do |path|
      from_paths << "#{user}@#{host}:#{path} "
    end  
    puts "Copying FROM remote TO this machine", $/
    
  else
    to_path = "#{user}@#{host}:#{to_path}"
    from_paths = paths.join(' ')
    puts "Copying FROM this machine TO remote", $/
  end
  
  
  cmd = "scp -r -i #{keypair} #{from_paths} #{to_path}"

  puts cmd if verbose
  printonly ? (puts cmd) : system(cmd)
end
