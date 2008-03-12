require 'cplus2ruby/code_generator'

class Cplus2Ruby::CppCodeGenerator < Cplus2Ruby::CodeGenerator
  DEFAULT_INCLUDES = [:"stdlib.h", "ruby.h"] 

  def write_RubyObject(out)
    pretty out, %[ 
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

  def write_includes(includes, out)
    includes.each do |inc|
      case inc
      when Symbol
        out << %{#include <#{inc}>\n}
      when String
        out << %{#include "#{inc}"\n}
      else
        raise "write_includes: invalid header"
      end
    end
  end

  def write_type_alias(from, to, out)
    out << "typedef #{to} #{from};\n"
  end

  # 
  # Type aliases is a hash in the form from => to.
  #
  def write_type_aliases(type_aliases, out)
    type_aliases.each do |from, to|
      write_type_alias(from, to, out)
    end
  end

  #
  # +kind+ is either :free or :mark
  #
  def write_free_or_mark_method(klass, kind, out)
    stmts = stmts_for_free_or_mark_method(klass, kind)
    pretty_body_unless_empty out, stmts, %[
      void
      #{klass.name}::__#{kind}__()
      {
        %%BODY%%
        super::__#{kind}__();
      }
    ]
  end

  def write_constructor_impl(klass, out)
    stmts = []
    all_properties_of(klass) do |name, options|
      init = @model.lookup_type_entry(:init, options, options[:type])
      stmts << @model.var_assgn("this->#{name}", init) unless init.nil?
    end

    pretty_body_unless_empty out, stmts, %[
      #{klass.name}::#{klass.name}()
      {
        %%BODY%%
      }
    ]
  end

  def write_property(name, options, out)
    out << @model.var_decl(options[:type], name) 
  end

  #
  # If +klassname+ is nil, then it doesn't include the
  # Klassname:: prefix. 
  #
  # Doesn't include the semicolon at the end.
  #
  def write_method_sig(klassname, name, options, out)
    args = options[:arguments].dup
    returns = args.delete(:returns) || "void"

    out << "static " if options[:static] 
    out << "inline " if options[:inline]
    out << "virtual " if options[:virtual]
    out << @model.var_decl(returns, "")
    out << "\n"

    s = args.map {|aname, atype| @model.var_decl(atype, aname) }.join(", ")

    out << "#{klassname}::" if klassname
    out << "#{name}(#{s})"
  end

  def write_method_body(options, out)
    pretty_body out, options[:body] || "", %[
      {
        %%BODY%%
      }
    ]
  end

  def write_class_declaration(klass, out)
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
    body = ""

    all_properties_of(klass) do |name, options|
      write_property(name, options, body)
      body << ";\n"
    end

    all_methods_of(klass) do |name, options|
      write_method_sig(nil, name, options, body)
      if options[:inline]
        body << "\n"
        write_method_body(options, body)
      else
        body << ";\n"
      end
    end
     
    pretty_body out, body, %[
      struct #{klass.name} : #{sc}
      {
        typedef #{sc} super;

        #{klass.name}();

        #{m[:free]}
        #{m[:mark]}
        
        %%BODY%%
      };
    ]
  end

  def write_class_impl(klass, out)
    # FIXME: helper_codes

    write_constructor_impl(klass, out)

    [:free, :mark].each {|kind|
      write_free_or_mark_method(klass, kind, out)
    }

    all_methods_of(klass) do |name, options|
      next if options[:inline]
      write_method_sig(klass.name, name, options, out)
      out << "\n"
      write_method_body(options, out)
    end
  end


  def write_header_file(out)
    write_includes(DEFAULT_INCLUDES + @model.includes, out)
    write_RubyObject(out)
    write_type_aliases(@model.type_aliases, out)
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
      write_class_declaration(klass, out)
    end
  end

  def write_impl_file(mod_name, out)
    out << %{#include "#{mod_name}.h"\n\n}

    #
    # class declarations
    #
    @model.entities_ordered.each do |klass|
      write_class_impl(klass, out)
    end
  end

  def create_files(mod_name)
    write_out(mod_name + ".h") {|out|
      write_header_file(out)
    }

    write_out(mod_name + ".cc") {|out|
      write_impl_file(mod_name, out)
    }
  end

  protected

  def stmts_for_free_or_mark_method(klass, kind)
    stmts = []
    all_properties_of(klass) do |name, options|
      if free_mark = @model.lookup_type_entry(kind, options, options[:type])
        stmts << free_mark.gsub('%s', "this->#{name}") # FIXME: use a common replacement function
      end
    end
    stmts
  end

end
