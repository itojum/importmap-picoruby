module ImportmapPicoRuby
  # Collects the calls of require / require_relative / load with a string
  # literal argument, wherever they are: top level, methods, blocks,
  # conditionals. Strings, comments, heredocs, =begin/=end, regexps and
  # everything after __END__ are skipped.
  #
  # Each result is a Hash: { kind: :require, path: "x", line: 3 }.
  # A call whose argument is not a plain string literal has path: nil.
  class Scanner
    KINDS = { "require" => :require, "require_relative" => :require_relative, "load" => :load }
    # After these keywords an expression starts (so `/` is a regexp, etc.)
    EXPR_KEYWORDS = %w[if unless while until and or not return when in case else elsif then do begin yield]

    def self.scan(source)
      new(source).scan
    end

    def initialize(source)
      @s = source
      @n = source.bytesize
      @i = 0
      @line = 1
      @bol = true          # at the beginning of a line
      @prev = :start       # :start/:op/:keyword => an expression may start
      @space = false       # whitespace right before the current token
      @heredocs = []
      @refs = []
    end

    def scan
      code(false)
      @refs
    end

    private

    def byte(i = @i)
      @s.getbyte(i)
    end

    def ident_start?(b)
      !b.nil? && ((b >= 97 && b <= 122) || (b >= 65 && b <= 90) || b == 95 || b >= 128)
    end

    def ident_char?(b)
      !b.nil? && (ident_start?(b) || (b >= 48 && b <= 57))
    end

    def expr_start?
      @prev == :start || @prev == :op || @prev == :keyword
    end

    # A token that may be the first argument of a command call: `foo /re/`
    def command_arg?
      @prev == :ident && @space && byte(@i + 1) != 32 && byte(@i + 1) != 61
    end

    # Scans code until EOF, or (when in_brace) until the "}" that closes
    # an interpolation.
    def code(in_brace)
      depth = 0
      while @i < @n
        b = byte
        if @bol
          @bol = false
          if b == 61 && @s.byteslice(@i, 6) == "=begin" && boundary?(@i + 6)
            skip_embdoc
            next
          end
          if b == 95 && @s.byteslice(@i, 7) == "__END__" && (@i + 7 == @n || byte(@i + 7) == 10 || byte(@i + 7) == 13)
            @i = @n
            return
          end
        end
        case b
        when 10
          newline
          @prev = :start unless @prev == :op
          @space = false
          next
        when 32, 9, 13, 12, 11
          @i += 1
          @space = true
          next
        when 92 # \ line continuation
          if byte(@i + 1) == 10
            @i += 2
            @line += 1
            read_heredocs
            @space = true
            next
          end
          @i += 1
          @prev = :op
        when 35 # #
          @i += 1 while @i < @n && byte != 10
          next
        when 39 # '
          @i += 1
          quoted(39, 39, false)
          @prev = :value
        when 34, 96 # " `
          @i += 1
          quoted(b, b, true)
          @prev = :value
        when 37 # %
          if (expr_start? || command_arg?) && percent_literal
            @prev = :value
          else
            @i += 1
            @i += 1 if byte == 61
            @prev = :op
          end
        when 47 # /
          @i += 1
          if expr_start? || command_arg?
            regexp
            @prev = :value
          else
            @i += 1 if byte == 61
            @prev = :op
          end
        when 63 # ?
          if (expr_start? || command_arg?) && char_literal
            @prev = :value
          else
            @i += 1
            @prev = :op
          end
        when 60 # <
          if byte(@i + 1) == 60 && (expr_start? || command_arg? || (@prev == :ident && @space)) && heredoc_start
            @prev = :value
          else
            @i += 1
            @i += 1 while byte == 60 || byte == 61 || byte == 62
            @prev = :op
          end
        when 58 # :
          if byte(@i + 1) == 58
            @i += 2
            @prev = :dot
          elsif byte(@i + 1) == 34 || byte(@i + 1) == 39
            q = byte(@i + 1)
            @i += 2
            quoted(q, q, q == 34)
            @prev = :value
          elsif ident_start?(byte(@i + 1)) && (expr_start? || @space || @prev == :value || @prev == :ident)
            @i += 1
            @i += 1 while ident_char?(byte)
            @i += 1 if byte == 63 || byte == 33 || byte == 61
            @prev = :value
          else
            @i += 1
            @prev = :op
          end
        when 36 # $
          @i += 1
          if ident_start?(byte)
            @i += 1 while ident_char?(byte)
          else
            @i += 1
          end
          @prev = :value
        when 64 # @
          @i += 1
          @i += 1 if byte == 64
          @i += 1 while ident_char?(byte)
          @prev = :value
        when 46 # .
          if byte(@i + 1) == 46
            @i += 2
            @i += 1 if byte == 46
            @prev = :op
          else
            @i += 1
            @prev = :dot
          end
        when 38 # &
          if byte(@i + 1) == 46
            @i += 2
            @prev = :dot
          else
            @i += 1
            @prev = :op
          end
        when 123 # {
          depth += 1
          @i += 1
          @prev = :op
        when 125 # }
          if in_brace && depth == 0
            @i += 1
            return
          end
          depth -= 1
          @i += 1
          @prev = :value
        when 41, 93 # ) ]
          @i += 1
          @prev = :value
        else
          if b >= 48 && b <= 57
            number
            @prev = :value
          elsif ident_start?(b)
            identifier
          else
            @i += 1
            @prev = :op
          end
        end
        @space = false
      end
    end

    def boundary?(i)
      b = byte(i)
      b.nil? || b == 32 || b == 9 || b == 10 || b == 13
    end

    def newline
      @i += 1
      @line += 1
      @bol = true
      read_heredocs
    end

    def skip_embdoc
      while @i < @n
        # skip the current line
        @i += 1 while @i < @n && byte != 10
        break if @i >= @n
        @i += 1
        @line += 1
        if @s.byteslice(@i, 4) == "=end" && boundary?(@i + 4)
          @i += 1 while @i < @n && byte != 10
          break
        end
      end
      @bol = false
    end

    def number
      while @i < @n
        b = byte
        if ident_char?(b)
          @i += 1
        elsif b == 46 && (c = byte(@i + 1)) && c >= 48 && c <= 57
          @i += 1
        else
          break
        end
      end
    end

    def identifier
      start = @i
      @i += 1 while ident_char?(byte)
      @i += 1 if (byte == 63 || byte == 33) && byte(@i + 1) != 61
      word = @s.byteslice(start, @i - start)
      if byte == 58 && byte(@i + 1) != 58 && @prev != :dot # label `foo:`
        @i += 1
        @prev = :op
        return
      end
      kind = KINDS[word]
      if kind && @prev != :dot && @prev != :def
        call_argument(kind)
      end
      @prev = if word == "def"
                :def
              elsif @prev == :dot || @prev == :def
                :value
              elsif EXPR_KEYWORDS.include?(word)
                :keyword
              elsif word == "end" || word == "self" || word == "nil" || word == "true" || word == "false"
                :value
              else
                :ident
              end
    end

    # Reads the argument of require/require_relative/load without moving @i.
    def call_argument(kind)
      j = @i
      j += 1 while byte(j) == 32 || byte(j) == 9
      paren = false
      if byte(j) == 40 # (
        paren = true
        j += 1
        j += 1 while byte(j) == 32 || byte(j) == 9 || byte(j) == 10 || byte(j) == 13
      elsif j == @i && byte(j) != 34 && byte(j) != 39
        return # `require` alone, `require.foo`, etc.
      end
      b = byte(j)
      return if b.nil? || b == 10 || b == 59 || (b == 41 && paren) || b == 61 || b == 46 || b == 125
      path = literal_at(j)
      @refs << { kind: kind, path: path, line: @line }
    end

    # The value of the string literal at j if it is plain, else nil.
    def literal_at(j)
      b = byte(j)
      if b == 39 || b == 34
        close = b
        j += 1
      elsif b == 37 && (byte(j + 1) == 113 || byte(j + 1) == 81) && !ident_char?(byte(j + 2)) && byte(j + 2) != 32
        open = byte(j + 2)
        close = closing(open)
        return nil if close != open # paired delimiters: keep it simple
        j += 3
      elsif b == 37 && byte(j + 1) && !ident_char?(byte(j + 1)) && byte(j + 1) != 32 && byte(j + 1) != 61
        open = byte(j + 1)
        close = closing(open)
        return nil if close != open
        j += 2
      else
        return nil
      end
      out = []
      while j < @n
        c = byte(j)
        return out.join if c == close
        return nil if c == 10
        if c == 92 # backslash
          d = byte(j + 1)
          return nil if d.nil?
          if d == close || d == 92
            out << d.chr
          else
            out << "\\" << d.chr
          end
          j += 2
          next
        end
        return nil if c == 35 && byte(j + 1) == 123 && close != 39 # interpolation
        start = j
        j += 1
        j += 1 while j < @n && byte(j) != close && byte(j) != 92 && byte(j) != 35 && byte(j) != 10
        out << @s.byteslice(start, j - start)
      end
      nil
    end

    def closing(open)
      case open
      when 40 then 41
      when 91 then 93
      when 123 then 125
      when 60 then 62
      else open
      end
    end

    # Skips a quoted literal; @i is just after the opening delimiter.
    def quoted(open, close, interp)
      depth = 0
      while @i < @n
        b = byte
        if b == 92
          @line += 1 if byte(@i + 1) == 10
          @i += 2
          next
        end
        if b == 10
          @i += 1
          @line += 1
          next
        end
        if interp && b == 35 && byte(@i + 1) == 123
          @i += 2
          saved = @prev
          @prev = :start
          code(true)
          @prev = saved
          next
        end
        if open != close && b == open
          depth += 1
        elsif b == close
          if depth == 0
            @i += 1
            return
          end
          depth -= 1
        end
        @i += 1
      end
    end

    # %w(...) %q[...] %(...) etc. Returns false when it is the % operator.
    def percent_literal
      t = byte(@i + 1)
      if t && ident_start?(t) && t < 128
        type = t.chr
        return false unless "qQwWiIrsx".include?(type)
        d = byte(@i + 2)
        return false if d.nil? || ident_char?(d) || d == 32 || d == 10
        @i += 3
      else
        type = "Q"
        d = t
        return false if d.nil? || d == 32 || d == 10 || d == 61 || ident_char?(d)
        @i += 2
      end
      interp = !"qwis".include?(type)
      quoted(d, closing(d), interp)
      @i += 1 while type == "r" && ident_char?(byte) # flags
      true
    end

    def regexp
      while @i < @n
        b = byte
        if b == 92
          @i += 2
          next
        end
        if b == 10
          @line += 1
        elsif b == 35 && byte(@i + 1) == 123
          @i += 2
          saved = @prev
          @prev = :start
          code(true)
          @prev = saved
          next
        elsif b == 91 # character class may contain an unescaped /
          @i += 1
          while @i < @n && byte != 93
            @i += 1 if byte == 92
            @line += 1 if byte == 10
            @i += 1
          end
        elsif b == 47
          @i += 1
          @i += 1 while ident_char?(byte)
          return
        end
        @i += 1
      end
    end

    # ?a ?\n => true; `cond ? a : b` => false
    def char_literal
      c = byte(@i + 1)
      return false if c.nil? || c == 32 || c == 10 || c == 9 || c == 13
      if c == 92
        len = 3
      else
        len = 2
        len += 1 while (x = byte(@i + len)) && x >= 128 && x < 192 # rest of a UTF-8 char
      end
      return false if ident_char?(byte(@i + len)) && c != 92
      @i += len
      true
    end

    def heredoc_start
      j = @i + 2
      squiggly = false
      if byte(j) == 126 || byte(j) == 45
        squiggly = true
        j += 1
      end
      q = byte(j)
      if q == 39 || q == 34 || q == 96
        close = @s.index(q.chr, j + 1)
        return false unless close
        id = @s.byteslice(j + 1, close - j - 1)
        return false if id.include?("\n")
        j = close + 1
      elsif ident_start?(q)
        start = j
        j += 1 while ident_char?(byte(j))
        id = @s.byteslice(start, j - start)
      else
        return false
      end
      @heredocs << [id, squiggly]
      @i = j
      true
    end

    # Called right after a newline: skips the bodies of pending heredocs.
    def read_heredocs
      return if @heredocs.empty?
      docs = @heredocs
      @heredocs = []
      docs.each do |id, squiggly|
        while @i < @n
          e = @s.index("\n", @i) || @n
          line = @s.byteslice(@i, e - @i)
          line = line.byteslice(0, line.bytesize - 1) if line.end_with?("\r")
          @i = e < @n ? e + 1 : @n
          @line += 1 if e < @n
          line = line.strip if squiggly
          break if line == id
        end
      end
      @bol = true
    end
  end
end
