#
# Cplus2Ruby
#
# Gluing C++ and Ruby together in an Object-oriented manner.  
#
# Author::    Michael Neumann
# Copyright:: (c) 2007, 2008 by Michael Neumann (mneumann@ntecs.de)
# License::   Released under the same terms as Ruby itself.
#

#
# Limitations:
#
# Modules are special in Cplus2Ruby, because they have to be "flat"
# and have to be closed at the time they are mixed in.
#

if RUBY_VERSION >= "1.9"
  OHash = Hash
else
  # Ordered Hash
  class OHash < Hash
    attr_reader :order

    def dup
      n = OHash.new
      each do |k, v|
        n[k] = v
      end
      n
    end

    def []=(k, v)
      @order ||= []
      @order << k unless @order.include?(k)
      super
    end

    def [](k)
      @order ||= []
      @order << k unless @order.include?(k)
      super
    end

    def delete(k)
      @order ||= []
      @order.delete(k)
      super
    end

    def update(hash)
      hash.each do |k,v|
        self[k] = v
      end
    end

    def keys
      @order ||= []
      @order
    end

    def each
      @order ||= []
      @order.each do |k|
        yield k, self[k]
      end
      self
    end

    def each_value
      @order ||= []
      @order.each do |k|
        yield self[k]
      end
      self
    end

    def all?
      each do |k, v|
        return false unless yield k, v
      end
      return true
    end
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
    case header
    when Symbol
      self << %{#include <#{header}>}
    when String
      self << %{#include "#{header}"}
    else
      raise ArgumentError
    end
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

  #
  # Called when Cplus2Ruby is included in another module or a class.
  # If a module is included in another module, then the module
  # to be included must be closed.
  #

  def self.append_features(mod, this=nil)
    super(mod)
    mod.extend(this || self)
    # also register a subclass
    def mod.inherited(k)
      Cplus2Ruby.model[k]
    end
    # transitive append_features
    def mod.append_features(k, this=nil)
      super(k)
      Cplus2Ruby.append_features(k, this||self)
    end
    #Cplus2Ruby.model[mod] # this will register the class

    # append all properties of "self" to mod.
    Cplus2Ruby.model[mod].append(Cplus2Ruby.model[this || self])
  end

  ###################################

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
    Cplus2Ruby.model[self].add_property(name, type, options)
  end

  def virtual(*args)
    args.each do |virt|
      Cplus2Ruby.model[self].add_virtual(virt)
    end
  end

  def properties
    Cplus2Ruby.model[self].properties
  end

  #
  # method :name, {hash}, {hash}, ..., {hash}, body, hash 
  #
  def method(name, *args)
    params = OHash.new
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

    Cplus2Ruby.model[self].add_method(name, params, body, options)
  end 

  alias method_c method

  def helper_header(body)
    Cplus2Ruby.model[self].add_helper_header(body)
  end

  def helper_code(body)
    Cplus2Ruby.model[self].add_helper_code(body)
  end

  def self.generate_code(mod)
    cg = Cplus2Ruby::CodeGenerator.new(Cplus2Ruby.model)
    cg.write(mod)
  end

  #
  # Compiles +file+ and loads it.
  #
  def self.compile_and_load(file, cflags="", libs="")
    require 'rbconfig'
    require 'win32/process' if RUBY_PLATFORM.match('mswin')
    require 'fileutils'

    RbConfig::MAKEFILE_CONFIG['COMPILE_C'] = 
      '$(CC) $(INCFLAGS) $(CPPFLAGS) $(CFLAGS) -c $<'
    RbConfig::MAKEFILE_CONFIG['COMPILE_CXX'] = 
      '$(CXX) $(INCFLAGS) $(CPPFLAGS) $(CXXFLAGS) -c $<'

    base = File.basename(file)
    dir = File.dirname(file)
    mod, ext = base.split(".") 

    FileUtils.mkdir_p(dir)

    make = RUBY_PLATFORM.match('mswin') ? 'nmake' : 'make'

    Dir.chdir(dir) do
      self.generate_code(mod)
      system("#{make} clean") if File.exist?('Makefile')

      #pid = fork do
        require 'mkmf'
        $CFLAGS = cflags
        $LIBS << (" -lstdc++ " + libs)
        create_makefile(mod)
        system "#{make}" # exec
      #end
      #_, status = Process.waitpid2(pid)

      #if RUBY_PLATFORM.match('mswin')
      #  raise if status != 0
      #else
      #  raise if status.exitstatus != 0
      #end
    end
    require "#{dir}/#{mod}.#{Config::CONFIG['DLEXT']}"
  end
end

class Cplus2Ruby::Entity
  def self.inherited(klass)
    super
    klass.class_eval "include ::Cplus2Ruby"
  end
end

Cplus2Ruby_ = Cplus2Ruby::Entity 

class Cplus2Ruby::Model
  attr_reader :type_aliases, :type_map, :code

  def initialize
    @model_classes = OHash.new
    @type_aliases = OHash.new
    @type_map = get_type_map()
    @code = ""
    @settings = {:substitute_iv_ats => true}

    add_type_alias Object => 'VALUE'
  end

  def settings(h={})
    @settings.update(h)
    @settings
  end

  def add_type_alias(h)
    @type_aliases.update(h)
    h.each do |from, to|
      @type_map[from] = @type_map[to]
    end
  end

  def new_model_class_for(klass)
    mk = Cplus2Ruby::Model::ModelClass.new(klass)
    @type_map[mk.klass] = object_type_map(mk.klass.name)
    mk
  end

  def [](klass)
    @model_classes[klass] ||= new_model_class_for(klass)
  end

  def each_model_class(&block)
    @model_classes.each_value do |mk|
      next if mk.is_module?
      block.call(mk)
    end
  end

  # 
  # Returns a C++ declaration
  #
  def type_encode(type, name)
    if entry = @type_map[type]
      entry[:ctype].gsub("%s", name.to_s)
    elsif type.include?("%s")
      type.gsub("%s", name.to_s)
    else
      "#{type} #{name}"
    end
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

  def get_type_entry(type)
    @type_map[type] || nil 
  end

  protected

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

  def get_type_map
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
end

class Cplus2Ruby::Model::ModelClass
  attr_reader :klass, :properties, :methods, :helper_headers, :helper_codes
  attr_reader :virtuals

  def initialize(klass)
    @klass = klass
    @properties = []
    @methods = []
    @helper_headers = []
    @helper_codes = []
    @virtuals = []
  end

  def append(mk)
    @properties.push(*mk.properties)
    @methods.push(*mk.methods)
    @helper_headers.push(*mk.helper_headers)
    @helper_codes.push(*mk.helper_codes)
    @virtuals.push(*mk.virtuals)
  end

  def is_module?
    !@klass.is_a?(Class)
  end

  def add_virtual(virt)
    @virtuals << virt
  end

  def add_property(name, type, options)
    type = type.to_s if type.is_a?(Symbol)
    @properties << Cplus2Ruby::Model::ModelProperty.new(name, type, options) 
  end

  def add_helper_header(body)
    @helper_headers << body
  end

  def add_helper_code(body)
    @helper_codes << body
  end

  def add_method(name, params, body, options)
    # Convert Symbols to strings for types
    nparams = OHash.new
    params.each {|k,v|
      v = v.to_s if v.is_a?(Symbol)
      nparams[k] = v
    }

    @methods << Cplus2Ruby::Model::ModelMethod.new(self, name, nparams, body, options)
  end
end

class Cplus2Ruby::Model::ModelProperty
  attr_reader :name, :type, :options
  def initialize(name, type, options)
    @name, @type, @options = name, type, options
  end

  def init(model)
    model.lookup_type_entry(:init, self.options, self.type)
  end
end

class Cplus2Ruby::Model::ModelMethod
  attr_accessor :name, :params, :body, :options
  def initialize(model_class, name, params, body, options)
    @model_class = model_class
    @name, @params, @body, @options = name, params, body, options
  end

  def arity
    n = @params.size
    n -= 1 if @params.include?(:returns)
    return n
  end

  def virtual?
    if options[:virtual]
      return true
    else
      mc = @model_class
      while mc
        return true if mc.virtuals.include?(@name)
        sc = mc.klass.superclass
        if sc and sc.ancestors.include?(Cplus2Ruby)
          mc = Cplus2Ruby.model[sc]
        else
          break
        end
      end
    end
    return false
  end

end

class Cplus2Ruby::CodeGenerator
  def initialize(model=Cplus2Ruby.model)
    @model = model
  end

  # 
  # Allows preprocessing of generated code.
  #
  def write_out(file, &block)
    block.call(str="")
    if @model.settings()[:substitute_iv_ats] 
      str.gsub!('@', 'this->')
    end
    File.open(file, 'w+') {|out| out << str}
  end

  def write(mod_name)
    #
    # mod_name.h
    #
    write_out(mod_name + ".h") do |out|
      header(out)
      type_aliases(out)
      out << @model.code

      forward_class_declarations(out)
      helper_headers(out)
      class_declarations(out)
    end
    
    #
    # mod_name.cc
    #
    write_out(mod_name + ".cc") do |out| 
      out << %{#include "#{mod_name}.h"\n\n}
      class_bodies(out)
    end
    
    #
    # mod_name_wrap.cc
    #
    write_out(mod_name + "_wrap.cc") do |out| 
      out << %{#include "#{mod_name}.h"\n\n}

      ruby_method_wrappers(out)
      ruby_property_wrappers(out)

      ruby_alloc(out)
      ruby_init(mod_name, out)
    end
  end

  def ruby_alloc(out)
    @model.each_model_class do |mk|
      out << "static VALUE\n"
      out << "#{mk.klass.name}_alloc__(VALUE klass)\n"
      out << "{\n"

      # Declare C++ object
      out << @model.type_encode(mk.klass, "cobj")
      out << ";\n"

      out << "cobj = new #{mk.klass.name}();\n"
      out << "cobj->__obj__ = "
      out << "Data_Wrap_Struct(klass, RubyObject::__mark, RubyObject::__free, cobj);\n"

      out << "return cobj->__obj__;\n"
      out << "}\n"
    end
  end

  def ruby_method_wrappers(out)
    @model.each_model_class do |mk|
      mk.methods.each do |meth|
        unless meth.params.all? {|_, type| can_convert_type?(type) }
          puts "warn: cannot wrap method #{ meth.name }"
          next
        end

        params = meth.params.dup
        returns = params.delete(:returns) || 'void'

        out << "static VALUE\n"
        out << "#{mk.klass.name}_wrap__#{meth.name}"
        out << "("
        out << (["VALUE __self__"] + params.map {|n,_| "VALUE #{n}"}).join(", ")
        out << ")\n"
        out << "{\n"

        # declare C++ return value 
        if returns != 'void'
          out << @model.type_encode(returns, "__res__") 
          out << ";\n"
        end

        # declare C++ object
        out << @model.type_encode(mk.klass, "__cobj__")
        out << ";\n"
        
        # convert __self__ to C++ object pointer
        ## FIXME: can remove!
        out << "Check_Type(__self__, T_DATA);\n"
        out << "__cobj__ = (#{mk.klass.name}*) DATA_PTR(__self__);\n"

        # check argument types
        params.each { |n, t| check_type(n, t, out) }
        
        # call arguments 
        cargs = params.map {|n, t| @model.get_type_entry(t)[:ruby2c].gsub('%s', n.to_s) }

        # build method call
        out << "__res__ = " if returns != 'void'

        out << "__cobj__->#{meth.name}(#{cargs.join(', ')});\n"

        # convert return value
        retv = @model.get_type_entry(returns)[:c2ruby].gsub('%s', '__res__')

        out << "  return #{retv};\n"
        out << "}\n"
      end
    end
  end

  def ruby_mark(model_class, out)
    out << "void #{model_class.klass.name}::__mark__() {\n"

    model_class.properties.each do |prop|
      if mark = @model.lookup_type_entry(:mark, prop.options, prop.type) 
        out << mark.gsub('%s', "this->#{prop.name}")
        out << ";\n"
      end
    end

    out << "super::__mark__();\n"

    out << "}\n"
  end

  def ruby_property_wrappers(out)
    @model.each_model_class do |mk|
      mk.properties.each do |prop|
        next unless can_convert_type?(prop.type)  

        ## getter
        out << "static VALUE\n"
        out << "#{mk.klass.name}_get__#{prop.name}(VALUE __self__)\n"
        out << "{\n"

        # declare C++ object
        out << @model.type_encode(mk.klass, "__cobj__")
        out << ";\n"
        
        # convert __self__ to C++ object pointer
        ## FIXME: can remove!
        out << "Check_Type(__self__, T_DATA);\n"
        out << "__cobj__ = (#{mk.klass.name}*) DATA_PTR(__self__);\n"
       
        # convert return value
        retv = @model.get_type_entry(prop.type)[:c2ruby].gsub('%s', "__cobj__->#{prop.name}")

        out << "  return #{retv};\n"
        out << "}\n"

        ## setter
        out << "static VALUE\n"
        out << "#{mk.klass.name}_set__#{prop.name}(VALUE __self__, VALUE __val__)\n"
        out << "{\n"

        # declare C++ object
        out << @model.type_encode(mk.klass, "__cobj__")
        out << ";\n"
        
        # convert __self__ to C++ object pointer
        ## FIXME: can remove!
        out << "Check_Type(__self__, T_DATA);\n"
        out << "__cobj__ = (#{mk.klass.name}*) DATA_PTR(__self__);\n"
       
        check_type('__val__', prop.type, out)

        out << "__cobj__->#{prop.name} = "
        out << @model.get_type_entry(prop.type)[:ruby2c].gsub('%s', '__val__')
        out << ";\n"

        out << "  return Qnil;\n"
        out << "}\n"

      end
    end
  end

  #
  # Free is not required in most cases.
  #
  def ruby_free(model_class, out)
    out << "void #{model_class.klass.name}::__free__() {\n"

    model_class.properties.each do |prop|
      if free = @model.lookup_type_entry(:free, prop.options, prop.type)
        out << mark.gsub('%s', "this->#{prop.name}")
        out << ";\n"
      end
    end

    out << "super::__free__();\n"
    out << "}\n"
  end

  def ruby_init(mod_name, out)
    out << %{extern "C" void Init_#{mod_name}()\n}
    out << "{\n"
    out << "VALUE klass;"

    @model.each_model_class do |mk|
      out << %{klass = rb_eval_string("#{mk.klass.name}");\n}
      out << "rb_define_alloc_func(klass, #{mk.klass.name}_alloc__);\n"

      mp = mk.klass.name

      mk.methods.each do |meth| 
        next unless meth.params.all? {|_, type| can_convert_type?(type) }
        out << %{rb_define_method(klass, "#{meth.name}", } 
        out << %{(VALUE(*)(...))#{mp}_wrap__#{meth.name}, #{meth.arity});\n}
      end

      mk.properties.each do |prop|
        next unless can_convert_type?(prop.type)  

        # getter
        out << %{rb_define_method(klass, "#{prop.name}", } 
        out << %{(VALUE(*)(...))#{mp}_get__#{prop.name}, 0);\n}

        # setter
        out << %{rb_define_method(klass, "#{prop.name}=", } 
        out << %{(VALUE(*)(...))#{mp}_set__#{prop.name}, 1);\n}
      end
    end

    out << "}\n"
  end

  # 
  # Return true if Ruby <-> C conversion for this type is possible
  #
  def can_convert_type?(type)
    @model.get_type_entry(type) ? true : false
  end

  def check_type(name, type, out)
    if checktype = @model.get_type_entry(type)[:ruby2c_checktype]
      out << checktype.gsub('%s', name.to_s) 
      out << ";\n"
    end
  end

  def forward_class_declarations(out)
    @model.each_model_class do |m|
      out << "struct #{m.klass.name};\n"
    end
  end

  def helper_headers(out)
    @model.each_model_class do |m|
      next if m.helper_headers.empty?
      out << "// helper header for class: #{m.klass.name}\n"
      out << m.helper_headers.join("\n")
    end
  end

  def class_declarations(out)
    # TODO: order accordingly?
    @model.each_model_class do |m|
      class_declaration(m, out)
    end
  end

  def class_bodies(out)
    # TODO: order accordingly?
    @model.each_model_class do |m|
      class_body(m, out)
    end
  end

  def class_declaration(model_class, out)
    out << "struct #{model_class.klass.name}"
    sc = model_class.klass.superclass
    if sc == Object or sc == Cplus2Ruby::Entity
      sc = "RubyObject"
    else
      sc = sc.name
    end
    out << " : #{sc}\n" if sc

    out << "{\n"

    # superclass shortcut
    out << "typedef #{sc} super;\n" if sc

    # declaration of constructor
    out << "// Constructor\n"
    out << "#{model_class.klass.name}();\n\n"

    # declaration of __mark__ and __free__ methods
    out << "// mark method\n"
    out << "virtual void __mark__();\n\n"

    out << "// free method\n"
    out << "virtual void __free__();\n\n"

    model_class.properties.each do |prop|
      property(prop, out)
    end

    model_class.methods.each do |meth|
      method_proto(meth, out)
    end

    out << "};\n"
  end

  def class_body(model_class, out)
    out << model_class.helper_codes.join("\n")

    constructor(model_class, out)
    ruby_mark(model_class, out)
    ruby_free(model_class, out)

    model_class.methods.each do |meth|
      method_body(meth, model_class, out)
    end
  end

  def constructor(model_class, out)
    n = model_class.klass.name
    out << "#{n}::#{n}() {\n"

    model_class.properties.each do |prop|
      init = @model.lookup_type_entry(:init, prop.options, prop.type)
      unless init.nil?
        if init.is_a?(String) and init.include?("%s")
          out << init.gsub('%s', "this->#{prop.name}")
        else
          out << "this->#{prop.name} = #{init}"
        end
        out << ";\n"
      end
    end

    out << "}\n"
  end
 
  def method_body(meth, model_class, out)
    return if meth.options[:inline]
    params = meth.params.dup
    returns = params.delete(:returns) || "void"

    out << @model.type_encode(returns, "")
    out << " "
    out << model_class.klass.name
    out << "::"
    out << meth.name.to_s
    out << "("
    out << params.map do |k, v|
      @model.type_encode(v, k)
    end.join(", ")
    out << ")"

    out << " {\n"
    if meth.body.nil?
      #out << %{rb_raise(rb_eRuntimeError, "abstract method #{meth.name} called");\n}
    else
      out << meth.body
    end
    out << "}\n"
  end

  def method_proto(meth, out)
    params = meth.params.dup
    returns = params.delete(:returns) || "void"

    out << "static " if meth.options[:static] 
    out << "inline " if meth.options[:inline]

    out << "virtual " if meth.virtual?

    out << @model.type_encode(returns, "")
    out << " "
    out << meth.name.to_s
    out << "("
    out << params.map do |k, v|
      @model.type_encode(v, k)
    end.join(", ")
    out << ")"

    if meth.options[:inline]
      out << "\n{"
      out << meth.body
      out << "}"
    else
      out << ";\n"
    end
  end

  def property(prop, out)
    out << @model.type_encode(prop.type, prop.name)
    out << ";\n"
  end

  def header(out)
    out << <<EOS
#include <stdlib.h>
#include "ruby.h"
struct RubyObject {

  VALUE __obj__;

  RubyObject() {
    __obj__ = Qnil;
  }

  virtual ~RubyObject() {};

  static void __free(void *ptr) {
    ((RubyObject*)ptr)->__free__();
  }

  static void __mark(void *ptr) {
    ((RubyObject*)ptr)->__mark__();
  }

  virtual void __free__() { delete this; }
  virtual void __mark__() { }
};
EOS
  end

  def type_aliases(out)
    @model.type_aliases.each do |from, to|
      out << "typedef #{to} #{from};"
    end
  end

end
