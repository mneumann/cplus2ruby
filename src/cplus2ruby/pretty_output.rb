module Cplus2Ruby::PrettyOutput
  def pretty_body_unless_empty(out, stmts, str)
    pretty_body(out, stmts, str) unless stmts.empty?
  end

  def pretty_body(out, stmts, str)
    out << pretty_str(str).gsub(/^(\s+)%%BODY%%[\n]/) {
      indent = $1
      if stmts.kind_of?(Array)
        stmts.map {|s| "#{indent}#{s};\n"}.join
      else
        stmts.split("\n").map {|l| "#{indent}#{l}\n"}.join
      end
    }
  end

  def pretty(out, str)
    out << pretty_str(str)
  end

  def pretty_str(str)
    lines = str.split("\n")
    indent = 0

    # remove leading empty lines.
    # use the first non-empty line as a reference
    # for indentation
    loop do 
      line = lines.shift
      break if line.nil?
      next if line.empty?
      indent = $1.size if line =~ /^(\s+)/
      lines.unshift(line)
      break
    end

    # remove trailing lines.
    lines.reverse!
    loop do 
      line = lines.shift
      break if line.nil?
      next if line.empty?
      lines.unshift(line)
      break
    end
    lines.reverse!

    lines.map {|line|
      if line[0, indent].strip.empty?
        line[indent..-1] || ""
      else
        line
      end
    }.join("\n")
  end
end
