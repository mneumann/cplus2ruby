require 'rubygems'
$LOAD_PATH.unshift '../lib'
require 'cplus2ruby'

module Mixin1; cplus2ruby
  property :a, :int
end

class A; cplus2ruby
  property :y, :int
end

class B < A; cplus2ruby
  include Mixin1
end

class C < B; cplus2ruby
  property :z, :int
end

Cplus2Ruby.commit('work/test_mixin', true)
t = B.new
t.y = 2
p t.y

t = C.new
t.z = 343333
p t.z
p t.y
