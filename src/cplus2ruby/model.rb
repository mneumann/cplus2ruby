module Cplus2Ruby; end

class Cplus2Ruby::Property; end
class Cplus2Ruby::Method; end

class Cplus2Ruby::Model
  require 'facets/orderedhash'

  attr_reader :type_aliases
  attr_reader :type_map
  attr_reader :code
  attr_reader :includes

  def initialize
    @type_aliases = OrderedHash.new
    @type_map = default_type_map() 
    @code = ""
    @includes = []

    @settings = default_settings()

    add_type_alias Object => 'VALUE'
  end

  def entities
    entities = []
    ObjectSpace.each_object(Class) {|o|
      entities << o if o.kind_of?(Cplus2Ruby::Entity)
    }
    entities
  end

  def entities_ordered
    entities().sort {|a, b|
      if a.ancestors.include?(b)
        1
      elsif b.ancestors.include?(a)
        -1
      else
        0
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

  #
  # Add a type alias. Also modifies type map.
  #
  def add_type_alias(h)
    @type_aliases.update(h)
    h.each do |from, to|
      @type_map[from] = @type_map[to]
    end
  end

  def get_type_entry(type)
    @type_map[type] || nil 
  end

  def lookup_type_entry(attribute, first, type)
    val = first[attribute]
    if val.nil? 
      if x = get_type_entry(type)
        val = x[attribute] 
      end
    end
    return val
  end

  # 
  # Returns a C++ declaration
  #
  def var_decl(type, name)
    if entry = get_type_entry(type)
      entry[:ctype].gsub("%s", name.to_s)
    # FIXME type.to_s
    elsif type.to_s.include?("%s")
      type.gsub("%s", name.to_s)
    else
      "#{type} #{name}"
    end
  end

  def var_assgn(name, value)
    raise ArgumentError if value.nil?
    if value.is_a?(String) and value.include?('%s')
      value.gsub('%s', name)
    else
      "#{name} = #{value}"
    end
  end

=begin
  def new_model_class_for(klass)
    mk = Cplus2Ruby::ModelClass.new(klass)
    @type_map[mk.klass] = object_type_map(mk.klass.name)
    return mk
  end
=end

  protected

  def default_type_map
    { 
      'VALUE' => {
        :init   => 'Qnil',
        :mark   => 'rb_gc_mark(%s)',
        :ruby2c => '%s',
        :c2ruby => '%s',
        :ctype  => 'VALUE %s' 
      },
      'float' => {
        :init   => 0.0,
        :ruby2c => '(float)NUM2DBL(%s)',
        :c2ruby => 'rb_float_new((double)%s)',
        :ctype  => 'float %s'
      },
      'double' => {
        :init   => 0.0,
        :ruby2c => '(double)NUM2DBL(%s)',
        :c2ruby => 'rb_float_new(%s)',
        :ctype  => 'double %s'
      },
      'int' => {
        :init   => 0,
        :ruby2c => '(int)NUM2INT(%s)',
        :c2ruby => 'INT2NUM(%s)',
        :ctype  => 'int %s'
      },
      'unsigned int' => {
        :init   => 0,
        :ruby2c => '(unsigned int)NUM2INT(%s)',
        :c2ruby => 'INT2NUM(%s)',
        :ctype  => 'unsigned int %s'
      },
      'bool' => { 
        :init   => false,
        :ruby2c => '(RTEST(%s) ? true : false)',
        :c2ruby => '(%s ? Qtrue : Qfalse)',
        :ctype  => 'bool %s'
      },
      'void' => {
        :c2ruby => 'Qnil',
        :ctype  => 'void'
      }
    }
  end

  def default_settings
    {
      :substitute_iv_ats => true
    }
  end

  def object_type_map(type)
    {
      :init   => "NULL",
      :mark   => "if (%s) rb_gc_mark(%s->__obj__)",
      :ruby2c => "(NIL_P(%s) ? NULL : (#{type}*)DATA_PTR(%s))",
      :c2ruby => "(%s ? %s->__obj__ : Qnil)", 
      :ctype  => "#{type} *%s",
      :ruby2c_checktype => "if (!NIL_P(%s)) Check_Type(%s, T_DATA)"
    }
  end

end

module Cplus2Ruby
  require 'facets/annotations'
  require 'facets/orderedhash'

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
    model.add_type_alias(h)
  end

  def self.compile(file, cflags="", libs="")
    require 'cplus2ruby/compiler'
    comp = Cplus2Ruby::Compiler.new(self.model)
    comp.generate_code(file)
    comp.compile(file, cflags, libs)
  end
end

module Cplus2Ruby::Entity
  def public(*args)
    # FIXME
    super
  end

  def protected(*args)
    # FIXME
    super
  end

  def private(*args)
    # FIXME
    super
  end

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

=begin
  def helper_header(body)
    for which class.
    ann! 
    Cplus2Ruby.model[self].add_helper_header(body)
  end

  def helper_code(body)
    Cplus2Ruby.model[self].add_helper_code(body)
  end
=end
end

class Module
  def cplus2ruby
    include Cplus2Ruby::Entity
    extend Cplus2Ruby::Entity
  end
end
