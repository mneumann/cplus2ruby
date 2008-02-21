#
# Ruby >= 1.9.0 required for this example!
#
require 'cplus2ruby'

class NeuralEntity < Cplus2Ruby_
  property :id
end

class Neuron < NeuralEntity
  property :potential,       'float'
  property :last_spike_time, 'float'
  property :pre_synapses

  method_c :stimulate, {at: 'float', weight: 'float'}, %{
    // This is C++ Code
    @potential += at*weight;
  }

  def initialize
    self.pre_synapses = []
  end
end

if __FILE__ == $0
  Cplus2Ruby.compile_and_load('work/neural') 
  n = Neuron.new
  n.id = "n1"
  n.potential = 1.0
  n.stimulate(1.0, 2.0)
  p n.potential # => 3.0
end
