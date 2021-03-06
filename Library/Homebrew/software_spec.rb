require 'forwardable'
require 'resource'
require 'checksum'
require 'version'
require 'build_options'
require 'dependency_collector'

class SoftwareSpec
  extend Forwardable

  attr_reader :build, :resources, :owner
  attr_reader :dependency_collector

  def_delegators :@resource, :stage, :fetch
  def_delegators :@resource, :download_strategy, :verify_download_integrity
  def_delegators :@resource, :checksum, :mirrors, :specs, :using, :downloader
  def_delegators :@resource, :url, :version, :mirror, *Checksum::TYPES

  def initialize url=nil, version=nil
    @resource = Resource.new(:default, url, version)
    @resources = {}
    @build = BuildOptions.new(ARGV.options_only)
    @dependency_collector = DependencyCollector.new
  end

  def owner= owner
    @resource.owner = owner
    resources.each_value { |r| r.owner = owner }
  end

  def resource? name
    resources.has_key?(name)
  end

  def resource name, &block
    if block_given?
      raise DuplicateResourceError.new(name) if resource?(name)
      resources[name] = Resource.new(name, &block)
    else
      resources.fetch(name) { raise ResourceMissingError.new(owner, name) }
    end
  end

  def option name, description=nil
    name = name.to_s if Symbol === name
    raise "Option name is required." if name.empty?
    raise "Options should not start with dashes." if name[0, 1] == "-"
    build.add(name, description)
  end

  def depends_on spec
    dep = dependency_collector.add(spec)
    build.add_dep_option(dep) if dep
  end

  def deps
    dependency_collector.deps
  end

  def requirements
    dependency_collector.requirements
  end
end

class HeadSoftwareSpec < SoftwareSpec
  def initialize url=nil, version=Version.new(:HEAD)
    super
  end

  def verify_download_integrity fn
    return
  end
end

class Bottle < SoftwareSpec
  attr_rw :root_url, :prefix, :cellar, :revision

  def_delegators :@resource, :url=

  def initialize
    super
    @revision = 0
    @prefix = '/usr/local'
    @cellar = '/usr/local/Cellar'
  end

  # Checksum methods in the DSL's bottle block optionally take
  # a Hash, which indicates the platform the checksum applies on.
  Checksum::TYPES.each do |cksum|
    class_eval <<-EOS, __FILE__, __LINE__ + 1
      def #{cksum}(val=nil)
        return @#{cksum} if val.nil?
        @#{cksum} ||= Hash.new
        case val
        when Hash
          key, value = val.shift
          @#{cksum}[value] = Checksum.new(:#{cksum}, key)
        end

        if @#{cksum}.has_key? bottle_tag
          @resource.checksum = @#{cksum}[bottle_tag]
        end
      end
    EOS
  end
end
