class Cplus2Ruby::Compiler
  require 'cplus2ruby/cpp_code_generator'
  require 'cplus2ruby/wrapper_code_generator'

  def initialize(model=Cplus2Ruby.model)
    @model = model
  end

  def generate_code(mod_name)
    cpp_cg = Cplus2Ruby::CppCodeGenerator.new(@model)
    wrap_cg = Cplus2Ruby::WrapperCodeGenerator.new(@model)
    cpp_cg.create_files(mod_name)
    wrap_cg.create_files(mod_name)
  end

  #
  # Compiles +file+. Returns the name of the shared object to
  # use by +require+.
  #
  def compile(file, cflags="", libs="")
    require 'rbconfig'
    require 'win32/process' if RUBY_PLATFORM.match('mswin')
    require 'fileutils'

    base = File.basename(file)
    dir = File.dirname(file)
    mod, ext = base.split(".") 

    FileUtils.mkdir_p(dir)

    make = RUBY_PLATFORM.match('mswin') ? 'nmake' : 'make'

    Dir.chdir(dir) do
      generate_code(mod)
      system("#{make} clean") if File.exist?('Makefile')

      pid = fork do
        require 'mkmf'
        $CFLAGS = cflags
        $LIBS << (" -lstdc++ " + libs)
        create_makefile(mod)
        system "#{make}" # exec
      end
      _, status = Process.waitpid2(pid)

      if RUBY_PLATFORM.match('mswin')
        raise if status != 0
      else
        raise if status.exitstatus != 0
      end
    end
    "#{dir}/#{mod}.#{Config::CONFIG['DLEXT']}"
  end
end
