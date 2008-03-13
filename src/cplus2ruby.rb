module Cplus2Ruby; end

require 'cplus2ruby/model'
require 'cplus2ruby/compiler'

#
# Extend facets/annotations
#
class Module
  def recursive_annotations
    res = {}
    ancestors.each { |ancestor|
      ancestor.annotations.each { |ref, hash|
        res[ref] ||= {}
        res[ref] += hash if hash
      }
    }
    res
  end

  def local_annotations
    recursive_annotations() - self.superclass.recursive_annotations()
  end
end
