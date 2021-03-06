require 'cplus2ruby/code_generator'

class Cplus2Ruby::CppCodeGenerator < Cplus2Ruby::CodeGenerator
  DEFAULT_INCLUDES = [:"stdlib.h", "ruby.h"] 

  def gen_rubyObject
    %[
      struct RubyObject {
        VALUE __obj__;
        RubyObject() { __obj__ = Qnil; }
        virtual ~RubyObject() {};
        static void __free(void *ptr) { ((RubyObject*)ptr)->__free__(); }
        static void __mark(void *ptr) { ((RubyObject*)ptr)->__mark__(); }
        virtual void __free__() { delete this; }
        virtual void __mark__() { }
      };
    ]
  end

  def gen_include(inc)
    "#include " + 
    case inc
    when Symbol
      %{<#{inc}>}
    when String
      %{"#{inc}"}
    else
      raise ArgumentError, "invalid header"
    end
  end

  def gen_includes(includes)
    includes.map {|inc| gen_include(inc) }.join("\n")
  end

  def gen_type_alias(from, to)
    "typedef #{to} #{from};"
  end

  # 
  # Type aliases is a hash in the form from => to.
  #
  def gen_type_aliases(type_aliases)
    type_aliases.map {|from, to| gen_type_alias(from, to) }.join("\n")
  end

  #
  # +kind+ is either :free or :mark
  #
  def gen_free_or_mark_method(klass, kind)
    stmts = stmts_for_free_or_mark_method(klass, kind)
    return "" if stmts.empty?
    stmts.unshift("super::__#{kind}__()")
    %[
      void #{klass.name}::__#{kind}__()
      {
        #{stmts.join(";\n")};
      }
    ]
  end

  def gen_constructor(klass)
    stmts = []
    all_properties_of(klass) do |name, options|
      init = @model.typing.lookup_entry(:init, options, options[:type])
      stmts << @model.typing.var_assgn("this->#{name}", init) unless init.nil?
    end
    #return "" if stmts.empty?
    %[
      #{klass.name}::#{klass.name}()
      {
        #{stmts.join(";\n")};
      }
    ]
  end

  def gen_property(name, options)
    @model.typing.var_decl(options[:type], name)
  end

  #
  # If +klassname+ is nil, then it doesn't include the
  # Klassname:: prefix. 
  #
  # Doesn't include the semicolon at the end.
  #
  def gen_method_sig(klassname, name, options, is_declaration)
    args = options[:arguments].dup
    returns = args.delete(:returns) || "void"

    out = ""
    if is_declaration
      out << "static " if options[:static] 
      out << "inline " if options[:inline]
      out << "virtual " if options[:virtual]
    end
    out << @model.typing.var_decl(returns, "")
    out << " "

    s = args.map {|aname, atype| @model.typing.var_decl(atype, aname) }.join(", ")

    out << "#{klassname}::" if klassname
    out << "#{name}(#{s})"
    return out
  end

  def gen_method_body(klassname, name, options)
    if options[:stub]
      gen_stub_method(klassname, name, options)
    else
      "{\n" + (options[:body] || @model.settings[:default_body_when_nil]) + "}\n"
    end
  end

  #
  # Generates a C++ method that forwards the call to the Ruby method
  # of the same name.
  #
  def gen_stub_method(klassname, name, options)
    raise "Stub method with body is invalid!" if options[:body]

    args = options[:arguments].dup
    unless args_convertable?(args)
      raise "ERROR: Cannot convert stub method #{klassname}::#{name}"
    end

    returns = args.delete(:returns) || "void"

    out = ""
    out << "{\n"
    out << "VALUE __res__ = " if returns != 'void'

    # TODO: move rb_intern out
    call_args = ["@__obj__", %{rb_intern("#{name}")}, args.size] + 
      args.map {|n, k| @model.typing.convert(k, n, :c2ruby) }

    out << %{rb_funcall(#{call_args.join(', ')});}

    # check return type
    if returns != 'void' 
      out << @model.typing.convert(returns, '__res__', :ruby2c_checktype)
      retval = @model.typing.convert(returns, '__res__', :ruby2c) 
      out << "return #{retval};\n"
    end

    out << "}\n"

    return out
  end

  def gen_method(klassname, name, options, include_body, is_declaration)
    str = gen_method_sig(klassname, name, options, is_declaration)
    str << gen_method_body(klassname, name, options) if include_body
    str
  end

  def gen_class_declaration(klass)
    if klass.superclass == Object
      sc = "RubyObject"
    else
      sc = klass.superclass.name
    end

    #
    # Do we have free or mark methods defined?
    #
    m = {}
    [:free, :mark].each do |kind|
      if not stmts_for_free_or_mark_method(klass, kind).empty?
        m[kind] = "virtual void __#{kind}__();"
      end
    end

    #
    # Write out property declarations and method signatures.
    #
    stmts = []

    all_properties_of(klass) {|name, options| 
      stmts << gen_property(name, options)
    }

    all_methods_of(klass) {|name, options|
      stmts << gen_method(nil, name, options, options[:inline], true)
    }
       
    if no_wrap?(klass)
      %[
        struct #{klass.name} 
        {
          #{stmts.join("; \n")};
        };
      ]
    else
      %[
        struct #{klass.name} : #{sc}
        {
          typedef #{sc} super;

          #{klass.name}();

          #{m[:free]}
          #{m[:mark]}
          
          #{stmts.join("; \n")};
        };
      ]
    end
  end

  def gen_class_impl(klass)
    # FIXME: helper_codes

    stmts = [] 

    if wrap?(klass)
      stmts << gen_constructor(klass)

      [:free, :mark].each {|kind| 
        stmts << gen_free_or_mark_method(klass, kind)
      }
    end

    all_methods_of(klass) do |name, options|
      next if options[:inline]
      stmts << gen_method(klass.name, name, options, true, false)
    end

    stmts.join("\n")
  end

  def gen_header_file
    out = ""
    out << gen_includes(DEFAULT_INCLUDES + @model.includes)
    out << gen_rubyObject()
    out << gen_type_aliases(@model.typing.aliases)
    out << @model.code

    # forward class declarations
    @model.entities_ordered.each do |klass|
      out << "struct #{klass.name};\n"
    end

    # FIXME: helper_headers

    #
    # class declarations
    #
    @model.entities_ordered.each do |klass|
      out << gen_class_declaration(klass)
    end

    return out
  end

  def gen_impl_file(mod_name)
    out = ""
    out << %{#include "#{mod_name}.h"\n\n}

    #
    # class declarations
    #
    @model.entities_ordered.each do |klass|
      out << gen_class_impl(klass)
    end

    return out
  end

  def write_files(mod_name)
    write_out(mod_name + ".h", gen_header_file())
    write_out(mod_name + ".cc", gen_impl_file(mod_name))
  end

  protected

  def stmts_for_free_or_mark_method(klass, kind)
    stmts = []
    all_properties_of(klass) do |name, options|
      if free_mark = @model.typing.lookup_entry(kind, options, options[:type])
        stmts << free_mark.gsub('%s', "this->#{name}") # FIXME: use a common replacement function
      end
    end
    stmts
  end

end
