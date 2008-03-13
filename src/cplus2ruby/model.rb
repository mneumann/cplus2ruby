require 'facets/annotations'
require 'facets/orderedhash'
require 'cplus2ruby/typing'

class Cplus2Ruby::Property; end
class Cplus2Ruby::Method; end

class Cplus2Ruby::Model
  attr_reader :typing
  attr_reader :code
  attr_reader :includes

  def next_order_cnt
    @order_cnt += 1
  end

  def initialize
    @typing = Cplus2Ruby::Typing.new
    @code = ""
    @includes = []
    @settings = default_settings()
    @order_cnt = 0
  end

  def finish!
    entities.each do |klass|
      @typing.add_object_type(klass)
    end
  end

  def entities
    entities = []
    ObjectSpace.each_object(Class) {|o|
      entities << o if o.kind_of?(Cplus2Ruby::Entity)
    }
    entities
  end

  def entity_usage(klass, other)
    usage_cnt = 0
    klass.local_annotations.each do |name, opts|
      usage_cnt += 1 if opts[:arguments] and opts[:arguments].values.include?(other)
      usage_cnt += 1 if opts[:type] and opts[:type] == other 
    end
    usage_cnt
  end

  def entities_ordered
    entities().sort {|a, b|
      if a.ancestors.include?(b)
        # a 'after' b (a > b)
        1
      elsif b.ancestors.include?(a)
        -1
      else
        ea = entity_usage(a, b)
        eb = entity_usage(b, a)

        if ea > 0 and eb == 0
          -1
        elsif eb > 0 and ea == 0 
          1
        else
          ao = (a.heritage(:__options__) || {})[:order] || 0
          bo = (b.heritage(:__options__) || {})[:order] || 0
          ao <=> bo
        end
      end
    }
  end

  #
  # Update or retrieve the current settings.
  #
  def settings(h={})
    @settings.update(h)
    @settings
  end

  protected

  def default_settings
    {
      :substitute_iv_ats => true
    }
  end

end

module Cplus2Ruby
  # 
  # Global code
  #
  def self.<<(code)
    model.code << "\n"
    model.code << code
    model.code << "\n"
  end

  def self.include(header)
    model.includes << header
  end

  def self.settings(h={})
    model.settings(h)
  end

  def self.model
    @model ||= Cplus2Ruby::Model.new
  end

  def self.add_type_alias(h)
    h.each {|from, to| model.typing.alias_entry(from, to)}
  end

  def self.startup(*args, &block)
    self.model.finish!
    Cplus2Ruby::Compiler.new(self.model).startup(*args, &block)
  end

  def self.compile(*args)
    self.model.finish!
    Cplus2Ruby::Compiler.new(self.model).compile(*args)
  end

end

module Cplus2Ruby::Entity
  def property(name, type=Object, options={})
    raise ArgumentError if options[:type]
    options[:type] = type
    ann! name, Cplus2Ruby::Property, options
  end

  #
  # method :name, {hash}, {hash}, ..., {hash}, body, hash 
  #
  def method(name, *args)
    params = OrderedHash.new
    body = nil
    options = {}

    state = :want_param

    while not args.empty?
      arg = args.shift

      case state
      when :want_param
        if arg.is_a?(Hash)
          params.update(arg)
        else
          args.unshift(arg)
          state = :want_body
        end
      when :want_body
        body = arg
        state = :want_options
      when :want_options
        raise unless arg.is_a?(Hash)
        raise unless args.empty?
        options = arg
      else
        raise
      end
    end

    options[:body] ||= body 
    options[:arguments] ||= params

    ann! name, Cplus2Ruby::Method, options 
  end 

  alias method_c method

  def virtual(*virtuals)
    virtuals.each do |name|
      ann! name, :virtual => true
    end
  end
end

class Module
  def cplus2ruby(hash={})
    include Cplus2Ruby::Entity
    extend Cplus2Ruby::Entity
    ann! :__options__, hash 
    ann! :__options__, :order => Cplus2Ruby.model.next_order_cnt if hash[:order].nil?
  end
end
