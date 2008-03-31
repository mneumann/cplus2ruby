class Cplus2Ruby::CodeGenerator
  require 'fileutils'

  def initialize(model=Cplus2Ruby.model)
    @model = model
  end

  # 
  # Allows preprocessing of generated code.
  #
  def write_out(file, str)
    if @model.settings()[:substitute_iv_ats] 
      str.gsub!('@', 'this->')
    end
    FileUtils.mkdir_p(File.dirname(file))
    File.open(file, 'w+') {|out| out.puts str}
  end

  def no_wrap?(klass)
    (klass.local_annotations[:__options__] || {})[:no_wrap]
  end

  def wrap?(klass)
    not no_wrap?(klass)
  end

  def all_properties_of(klass)
    klass.local_annotations.each do |name, options|
      next if options[:class] != Cplus2Ruby::Property
      yield name, options
    end
  end

  def all_methods_of(klass)
    klass.local_annotations.each do |name, options|
      next if options[:class] != Cplus2Ruby::Method
      yield name, options
    end
  end

  def args_convertable?(args)
    #FIXME: Facets 2.3.0 has a bug in Dictionary#all?
    ##args.all? {|_, type| @model.typing.can_convert?(type) }
    args.each {|_, type| return false unless @model.typing.can_convert?(type) }
    return true
  end

  def arity(args)
    # FIXME: Facets 2.3.0 has a bug in OrderedHash#include?
    # (it behaves differently than Hash)
    args.size - ((args.has_key?('returns') || args.has_key?(:returns)) ? 1 : 0)
  end 

end
