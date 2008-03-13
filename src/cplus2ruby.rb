module Cplus2Ruby; end

require 'cplus2ruby/model'
require 'cplus2ruby/compiler'

#
# Extend facets/annotations
#
class Module
  def recursive_annotations
    res = {}
    ancestors.reverse.each { |ancestor|
      ancestor.annotations.each { |ref, hash|
        res[ref] ||= {}
        res[ref].update(hash) if hash
      }
    }
    res
  end

  def local_annotations
    new_keys = recursive_annotations().keys - self.superclass.recursive_annotations().keys
    all_keys = new_keys + annotations().keys
    h = {}
    all_keys.each do |key|
      h[key] = heritage(key)
    end
    h
  end
end
