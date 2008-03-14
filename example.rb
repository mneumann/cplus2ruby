require 'rubygems'
$LOAD_PATH.unshift './src'
require 'cplus2ruby'

class NeuralEntity; cplus2ruby
  property :id
end

class Neuron < NeuralEntity
  property :potential,       :float
  property :last_spike_time, :float
  property :pre_synapses

  method :stimulate, {:at => :float},{:weight => :float}, %{
    // This is C++ Code
    @potential += at*weight;

    // call a Ruby method
    log(@potential);
  }

  stub_method :log, {:pot => :float}

  def log(pot)
    puts "log(#{pot})"
  end

  def initialize
    self.pre_synapses = []
  end
end

if __FILE__ == $0
  #
  # Generate C++ code, compile and load shared library. 
  #
  Cplus2Ruby.startup('work/neural') 

  n = Neuron.new
  n.id = "n1"
  n.potential = 1.0
  n.stimulate(1.0, 2.0)
  p n.potential # => 3.0
end
