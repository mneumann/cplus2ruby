class Cplus2Ruby::Compiler
  require 'cplus2ruby/cpp_code_generator'
  require 'cplus2ruby/wrapper_code_generator'

  def initialize(model=Cplus2Ruby.model)
    @model = model
  end

  def write_files(mod_name)
    cpp_cg = Cplus2Ruby::CppCodeGenerator.new(@model)
    wrap_cg = Cplus2Ruby::WrapperCodeGenerator.new(@model)
    cpp_cg.write_files(mod_name)
    wrap_cg.write_files(mod_name)
  end

  def startup(file, force_compilation=false, cflags="", libs="", &block) 
    n = names(file)

    if not force_compilation
      begin
        require n[:ld]
        block.call if block
        return
      rescue LoadError
      end
    end

    compile(file, cflags, libs)
    require n[:ld]
    block.call if block
  end

  #
  # Compiles +file+. Returns the name of the shared object to
  # use by +require+.
  #
  def compile(file, cflags="", libs="")
    n = names(file)

    require 'win32/process' if RUBY_PLATFORM.match('mswin')
    require 'fileutils'

    FileUtils.mkdir_p(n[:dir])

    make = RUBY_PLATFORM.match('mswin') ? 'nmake' : 'make'

    Dir.chdir(n[:dir]) do
      system("#{make} clean") if File.exist?('Makefile')
      write_files(n[:mod])

      pid = fork do
        require 'mkmf'
        $CFLAGS = cflags
        $LIBS << (" -lstdc++ " + libs)
        create_makefile(n[:mod])
        exec "#{make}"
      end
      _, status = Process.waitpid2(pid)

      if RUBY_PLATFORM.match('mswin')
        raise if status != 0
      else
        raise if status.exitstatus != 0
      end
    end

    return n[:ld]
  end

  def names(file) 
    require 'rbconfig'
    base = File.basename(file)
    dir = File.dirname(file)
    mod, ext = base.split(".") 
    ld = "#{dir}/#{mod}.#{Config::CONFIG['DLEXT']}"
    { :file => file,
      :base => base,
      :dir  => dir,
      :mod  => mod,
      :ext  => ext,
      :ld   => ld }
  end

end
