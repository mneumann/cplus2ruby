class Cplus2Ruby::CodeGenerator
  require 'fileutils'
  require 'cplus2ruby/pretty_output'
  include Cplus2Ruby::PrettyOutput

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
    FileUtils.mkdir_p(File.dirname(file))
    File.open(file, 'w+') {|out| out << str}
  end

  def all_properties_of(klass)
    klass.annotations.each do |name, options|
      next if options[:class] != Cplus2Ruby::Property
      yield name, options
    end
  end

  def all_methods_of(klass)
    klass.annotations.each do |name, options|
      next if options[:class] != Cplus2Ruby::Method
      yield name, options
    end
  end
end
