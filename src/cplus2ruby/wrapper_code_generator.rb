require 'cplus2ruby/code_generator'

class Cplus2Ruby::WrapperCodeGenerator < Cplus2Ruby::CodeGenerator
  def write_allocator_function(klass, out)
    pretty out, %[
      static VALUE
      #{klass.name}_alloc__(VALUE klass)
      {
        #{klass.name} *__cobj__;
        __cobj__ = new #{klass.name}();
        __cobj__->__obj__ = Data_Wrap_Struct(klass, RubyObject::__mark, RubyObject::__free, __cobj__);
        return __cobj__->__obj__;
      }
    ]
  end

  def write_method_wrapper(klass, name, options, out)
    write_wrapper(klass, name, options, :wrap, out)
  end

  def write_property_getter(klass, name, options, out)
    opts = options.dup
    opts[:arguments] = {:returns => options[:type]}
    write_wrapper(klass, name, opts, :get, out)
  end

  def write_property_setter(klass, name, options, out)
    opts = options.dup
    opts[:arguments] = {:__val__ => options[:type]}
    write_wrapper(klass, name, opts, :set, out)
  end

  def write_property_accessor(klass, name, options, out)
    write_property_getter(klass, name, options, out)
    write_property_setter(klass, name, options, out)
  end

  def args_convertable?(args)
    args.all? {|_, type| can_convert_type?(type) }
  end

  def arity(args)
    args.size - (args.include?(:returns) ? 1 : 0)
  end 

  #
  # kind is one of :set, :get, :wrap
  #
  def write_wrapper(klass, name, options, kind, out)
    args = options[:arguments].dup
    unless args_convertable?(args)
      STDERR.puts "WARN: cannot wrap method #{klass.name}::#{name} (#{kind})"
      return
    end
    returns = args.delete(:returns) || "void"

    s = ([["__self__", "VALUE"]] + args.to_a).map {|n,_| "VALUE #{n}"}.join(", ")

    out << "static VALUE\n"
    out << "#{klass.name}_#{kind}__#{name}(#{s})\n"
    out << "{\n"

    # declare C++ return value
    if returns != 'void'
      out << @model.var_decl(returns, '__res__') + ";\n"
    end
    
    # declare C++ object reference
    out << "#{klass.name} *__cobj__;\n"
    #out << @model.var_decl(klass, '__cobj__') + ";\n"

    # convert __self__ to C++ object reference (FIXME: can remove?)
    out << "Check_Type(__self__, T_DATA);\n"
    out << "__cobj__ = (#{klass.name}*) DATA_PTR(__self__);\n"

    # check argument types
    args.each {|n, t| write_checktype(n, t, out) }

    # call arguments
    call_args = args.map {|n, t| convert_ruby2c(t, n.to_s)}

    # build method call
    out << "__res__ = " if returns != 'void'
    case kind
    when :wrap
      out << "__cobj__->#{name}(#{call_args.join(', ')});\n"
    when :get
      out << "__cobj__->#{name};\n"
    when :set
      raise ArgumentError if call_args.size != 1
      out << "__cobj__->#{name} = #{call_args.first};\n"
    else
      raise ArgumentError
    end

    # convert return value
    retval = convert_c2ruby(returns, '__res__')

    out << "return #{retval};\n"
    out << "}\n"
  end

  def write_init(mod_name, out)
    out << %[extern "C" void Init_#{mod_name}()\n]
    out << "{\n"
    out << "  VALUE klass;\n"

    @model.entities_ordered.each do |klass| 
      n = klass.name
      out << %{  klass = rb_eval_string("#{n}");\n}
      out << %{  rb_define_alloc_func(klass, #{n}_alloc__);\n}

      all_methods_of(klass) do |name, options|
        args = options[:arguments]
        next unless args_convertable?(args)
        out << %{  rb_define_method(klass, "#{name}", } 
        out << %{(VALUE(*)(...))#{n}_wrap__#{name}, #{arity(args)});\n}
      end

      all_properties_of(klass) do |name, options|
        next unless can_convert_type?(options[:type])

        # getter
        out << %{  rb_define_method(klass, "#{name}", } 
        out << %{(VALUE(*)(...))#{n}_get__#{name}, 0);\n}

        # setter
        out << %{rb_define_method(klass, "#{name}=", } 
        out << %{(VALUE(*)(...))#{n}_set__#{name}, 1);\n}
      end
    end

    out << "}\n"
  end

  def write_wrapper_file(mod_name, out)
    out << %{#include "#{mod_name}.h"\n\n}

    @model.entities_ordered.each do |klass| 
      write_allocator_function(klass, out)

      all_methods_of(klass) do |name, options|
        write_method_wrapper(klass, name, options, out)
      end

      all_properties_of(klass) do |name, options|
        write_property_accessor(klass, name, options, out)
      end
    end

    write_init(mod_name, out)
  end

  def create_files(mod_name)
    write_out(mod_name + "_wrap.cc") {|out|
      write_wrapper_file(mod_name, out)
    }
  end

  def write_checktype(name, type, out)
    if checktype = @model.get_type_entry(type)[:ruby2c_checktype]
      out << checktype.gsub('%s', name.to_s) 
      out << ";\n"
    end
  end

  protected

  # 
  # Return true if Ruby <-> C conversion for this type is possible
  #
  def can_convert_type?(type)
    @model.get_type_entry(type) ? true : false
  end

  def convert_c2ruby(type, var)
    convert(type, var, :c2ruby)
  end

  def convert_ruby2c(type, var)
    convert(type, var, :ruby2c)
  end

  def convert(type, var, kind)
    @model.get_type_entry(type)[kind].gsub('%s', var)
  end

end
