// An exact rational, the counterpart of Python's fractions.Fraction: the examples are exact.
package z3scala

final case class Rational private (n: BigInt, d: BigInt) extends Ordered[Rational]:
  def +(o: Rational): Rational = Rational(n * o.d + o.n * d, d * o.d)
  def -(o: Rational): Rational = Rational(n * o.d - o.n * d, d * o.d)
  def *(o: Rational): Rational = Rational(n * o.n, d * o.d)
  def /(o: Rational): Rational = Rational(n * o.d, d * o.n)
  def compare(o: Rational): Int = (n * o.d).compare(o.n * d)
  override def toString: String = if d == 1 then n.toString else s"$n/$d"

object Rational:
  def apply(n: BigInt, d: BigInt = 1): Rational =
    require(d != 0, "zero denominator")
    val g = n.gcd(d)
    val s = if d < 0 then -1 else 1
    new Rational(s * n / g, s * d / g)
  given Conversion[Int, Rational] = Rational(_)
  val zero: Rational = Rational(0)
