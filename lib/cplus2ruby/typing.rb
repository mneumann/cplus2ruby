class Cplus2Ruby::Typing
  require 'facets/orderedhash'

  attr_reader :aliases

  def initialize
    @map = default_map() 
    @aliases = OrderedHash.new
    clone_entry Object, 'VALUE'
  end

  def add_entry(type, entry)
    type = to_key(type)
    raise if @map.include?(type)
    @map[type] = entry
  end

  def clone_entry(from, to)
    from = to_key(from)
    to = to_key(to)
    raise if @map.include?(from)
    @map[from] = @map[to] # FIXME: .dup?
  end

  #
  # Add a type alias. Also modifies type map.
  #
  def alias_entry(from, to)
    from = to_key(from)
    to = to_key(to)
    @aliases[from] = to
    clone_entry(from, to)
  end

  def get_entry(type)
    @map[to_key(type)]
  end

  #
  # Looks up first in the annotation options, then 
  # in the type options.
  #
  def lookup_entry(attribute, options, type)
    (get_entry(type) || {}).dup.update(options)[attribute]
  end

  # 
  # Returns a C++ declaration
  #
  def var_decl(type, name)
    if entry = get_entry(type)
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

  # 
  # Returns true if Ruby <-> C conversion for this type is possible
  #
  def can_convert?(type)
    get_entry(type) ? true : false
  end

  def convert(type, var, kind)
    (get_entry(type)[kind] || "").gsub('%s', var.to_s)
  end

  def add_object_type(klass)
    add_entry(klass, object_type(klass.name))
  end

  protected

  def to_key(type)
    if type.is_a?(Symbol)
      type.to_s
    else
      type
    end
  end

  def object_type(type)
    {
      :init   => "NULL",
      :mark   => "if (%s) rb_gc_mark(%s->__obj__)",
      :ruby2c => "(NIL_P(%s) ? NULL : (#{type}*)DATA_PTR(%s))",
      :c2ruby => "(%s ? %s->__obj__ : Qnil)", 
      :ctype  => "#{type} *%s",
      :ruby2c_checktype => "if (!NIL_P(%s)) Check_Type(%s, T_DATA)"
    }
  end

  def default_map
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
