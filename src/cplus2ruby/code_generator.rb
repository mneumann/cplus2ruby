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
end
