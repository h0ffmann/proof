// A small JSON reader: Coverage.scala reads WW3's switches.json, and the build has one dependency,
// Z3. Objects become Map[String, Any], arrays List[Any], numbers Double, and null None.
package z3scala.kernel.text

object Json:
  def parse(text: String): Any =
    val p = Parser(text)
    val v = p.value()
    p.space()
    if p.i != text.length then sys.error(s"JSON: trailing text at ${p.i}")
    v

  final private class Parser(s: String):
    var i = 0
    def space(): Unit = while i < s.length && " \t\r\n".indexOf(s.charAt(i)) >= 0 do i += 1
    def expect(c: Char): Unit =
      space()
      if i >= s.length || s.charAt(i) != c then sys.error(s"JSON: expected '$c' at $i")
      i += 1
    def value(): Any =
      space()
      s.charAt(i) match
        case '{' => obj()
        case '[' => arr()
        case '"' => str()
        case 't' => word("true", true)
        case 'f' => word("false", false)
        case 'n' => word("null", None)
        case _   => number()
    def word(w: String, v: Any): Any =
      if !s.startsWith(w, i) then sys.error(s"JSON: bad token at $i")
      i += w.length
      v
    def number(): Double =
      val start = i
      while i < s.length && "+-0123456789.eE".indexOf(s.charAt(i)) >= 0 do i += 1
      s.substring(start, i).toDouble
    def str(): String =
      expect('"')
      val b = new StringBuilder
      while s.charAt(i) != '"' do
        if s.charAt(i) == '\\' then
          i += 1
          s.charAt(i) match
            case 'n' => b += '\n'
            case 't' => b += '\t'
            case 'r' => b += '\r'
            case 'b' => b += '\b'
            case 'f' => b += '\f'
            case 'u' =>
              b += Integer.parseInt(s.substring(i + 1, i + 5), 16).toChar
              i += 4
            case other => b += other
        else b += s.charAt(i)
        i += 1
      i += 1
      b.toString
    def arr(): List[Any] =
      expect('[')
      space()
      if s.charAt(i) == ']' then
        i += 1
        Nil
      else
        val b = List.newBuilder[Any]
        b += value()
        space()
        while s.charAt(i) == ',' do
          i += 1
          b += value()
          space()
        expect(']')
        b.result()
    def obj(): Map[String, Any] =
      expect('{')
      space()
      if s.charAt(i) == '}' then
        i += 1
        Map.empty
      else
        val b = Map.newBuilder[String, Any]
        def pair(): Unit =
          val k = str()
          expect(':')
          b += k -> value()
          space()
        space()
        pair()
        while s.charAt(i) == ',' do
          i += 1
          space()
          pair()
        expect('}')
        b.result()
