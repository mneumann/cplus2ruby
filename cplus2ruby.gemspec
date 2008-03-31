require 'rubygems'

spec = Gem::Specification.new do |s|
  s.name = "cplus2ruby"
  s.version = "1.1.1"
  s.summary = "Gluing C++ and Ruby together in an OO manner"
  s.files = Dir['**/*']
  s.add_dependency('facets', '>= 2.3.0')
  s.requirements << "On Window: gem win32-process"
  s.requirements << "C++ compiler and make"

  s.author = "Michael Neumann"
  s.email = "mneumann@ntecs.de"
  s.homepage = "http://www.ntecs.de/projects/cplus2ruby/"
  s.rubyforge_project = "cplus2ruby"
end

if __FILE__ == $0
  Gem::manage_gems
  Gem::Builder.new(spec).build
end
