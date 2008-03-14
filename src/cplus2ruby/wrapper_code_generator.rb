require 'cplus2ruby/code_generator'

class Cplus2Ruby::WrapperCodeGenerator < Cplus2Ruby::CodeGenerator
  def gen_allocator(klass)
    %[
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

  def gen_method_wrapper(klass, name, options)
    gen_wrapper(klass, name, options, :wrap)
  end

  def gen_property_getter(klass, name, options)
    opts = options.dup
    opts[:arguments] = {:returns => options[:type]}
    gen_wrapper(klass, name, opts, :get)
  end

  def gen_property_setter(klass, name, options)
    opts = options.dup
    opts[:arguments] = {:__val__ => options[:type]}
    gen_wrapper(klass, name, opts, :set)
  end

  def gen_property_accessor(klass, name, options)
    [gen_property_getter(klass, name, options),
     gen_property_setter(klass, name, options)].join
  end

  #
  # kind is one of :set, :get, :wrap
  #
  def gen_wrapper(klass, name, options, kind)
    args = options[:arguments].dup
    return nil if options[:stub]
    unless args_convertable?(args)
      STDERR.puts "WARN: cannot wrap method #{klass.name}::#{name} (#{kind})"
      return nil
    end

    returns = args.delete(:returns) || "void"

    s = ([["__self__", "VALUE"]] + args.to_a).map {|n,_| "VALUE #{n}"}.join(", ")

    out = ""
    out << "static VALUE\n"
    out << "#{klass.name}_#{kind}__#{name}(#{s})\n"
    out << "{\n"

    # declare C++ return value
    if returns != 'void'
      out << @model.typing.var_decl(returns, '__res__') + ";\n"
    end
    
    # declare C++ object reference
    out << "#{klass.name} *__cobj__;\n"
    #out << @model.var_decl(klass, '__cobj__') + ";\n"

    # convert __self__ to C++ object reference (FIXME: can remove?)
    out << "Check_Type(__self__, T_DATA);\n"
    out << "__cobj__ = (#{klass.name}*) DATA_PTR(__self__);\n"

    # check argument types
    out << args.map {|n, t| @model.typing.convert(t, n.to_s, :ruby2c_checktype) + ";\n" }.join

    # call arguments
    call_args = args.map {|n, t| @model.typing.convert(t, n.to_s, :ruby2c)}

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
    retval = @model.typing.convert(returns, '__res__', :c2ruby)

    out << "return #{retval};\n"
    out << "}\n"

    return out
  end

  def gen_init(mod_name)
    out = ""
    out << %[extern "C" void Init_#{mod_name}()\n]
    out << "{\n"
    out << "  VALUE klass;\n"

    @model.entities_ordered.each do |klass| 
      next if no_wrap?(klass)
      n = klass.name
      out << %{  klass = rb_eval_string("#{n}");\n}
      out << %{  rb_define_alloc_func(klass, #{n}_alloc__);\n}

      all_methods_of(klass) do |name, options|
        args = options[:arguments]
        next unless args_convertable?(args)
        next if options[:stub]
        out << %{  rb_define_method(klass, "#{name}", } 
        out << %{(VALUE(*)(...))#{n}_wrap__#{name}, #{arity(args)});\n}
      end

      all_properties_of(klass) do |name, options|
        next unless @model.typing.can_convert?(options[:type])

        # getter
        out << %{  rb_define_method(klass, "#{name}", } 
        out << %{(VALUE(*)(...))#{n}_get__#{name}, 0);\n}

        # setter
        out << %{rb_define_method(klass, "#{name}=", } 
        out << %{(VALUE(*)(...))#{n}_set__#{name}, 1);\n}
      end
    end

    out << "}\n"

    return out
  end

  def gen_wrapper_file(mod_name)
    out = ""
    out << %{#include "#{mod_name}.h"\n\n}

    @model.entities_ordered.each do |klass| 
      next if no_wrap?(klass)

      out << gen_allocator(klass)

      all_methods_of(klass) do |name, options|
        out << (gen_method_wrapper(klass, name, options) || "")
      end

      all_properties_of(klass) do |name, options|
        out << gen_property_accessor(klass, name, options)
      end
    end

    out << gen_init(mod_name)

    return out
  end

  def write_files(mod_name)
    write_out(mod_name + "_wrap.cc", gen_wrapper_file(mod_name))
  end

end
