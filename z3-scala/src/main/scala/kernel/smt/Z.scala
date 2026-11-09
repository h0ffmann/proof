// The shared kernel's language: Z3's Java API with operators, so that a statement reads as the
// sentence it proves. Every bounded context writes its statements in it; z3scala.kernel.proof
// says how a statement is proved.
package z3scala.kernel.smt

import com.microsoft.z3.*

import scala.language.implicitConversions

type Real = ArithExpr[ArithSort]
type Bool = BoolExpr
type BV = BitVecExpr
type FP = FPExpr

// -language:strictEquality: the solver's answers are compared with ==.
given CanEqual[Status, Status] = CanEqual.derived

object Z:
  lazy val ctx: Context = new Context()

  def real(name: String): Real = ctx.mkRealConst(name).asInstanceOf[Real]
  def reals(names: String): List[Real] = names.split(" ").toList.map(real)
  def int(name: String): Real = ctx.mkIntConst(name).asInstanceOf[Real]
  def bool(name: String): Bool = ctx.mkBoolConst(name)
  def num(n: Int): Real = ctx.mkReal(n).asInstanceOf[Real]
  def num(q: Rational): Real = ctx.mkReal(q.toString).asInstanceOf[Real]
  def num(s: String): Real = ctx.mkReal(s).asInstanceOf[Real]
  def intVal(n: Long): Real = ctx.mkInt(n).asInstanceOf[Real]
  def toReal(i: Real): Real = ctx.mkInt2Real(i.asInstanceOf[Expr[IntSort]]).asInstanceOf[Real]
  def boolVal(b: Boolean): Bool = ctx.mkBool(b)
  val True: Bool = boolVal(true)
  val False: Bool = boolVal(false)

  def and(bs: Bool*): Bool = if bs.isEmpty then True else ctx.mkAnd(bs*)
  def or(bs: Bool*): Bool = ctx.mkOr(bs*)
  def not(b: Bool): Bool = ctx.mkNot(b)
  def implies(a: Bool, b: Bool): Bool = ctx.mkImplies(a, b)
  def xor(a: Bool, b: Bool): Bool = ctx.mkXor(a, b)
  def ite(c: Bool, a: Real, b: Real): Real = ctx.mkITE(c, a, b).asInstanceOf[Real]
  def iteB(c: Bool, a: Bool, b: Bool): Bool = ctx.mkITE(c, a, b).asInstanceOf[Bool]
  def sum(xs: Iterable[Real]): Real = xs.foldLeft(num(0))(_ + _)

  given Conversion[Int, Real] = num(_)
  given Conversion[Rational, Real] = num(_)

  extension (a: Real)
    def +(b: Real): Real = ctx.mkAdd(a, b)
    def -(b: Real): Real = ctx.mkSub(a, b)
    def *(b: Real): Real = ctx.mkMul(a, b)
    def /(b: Real): Real = ctx.mkDiv(a, b)
    def unary_- : Real = ctx.mkUnaryMinus(a)
    def <(b: Real): Bool = ctx.mkLt(a, b)
    def <=(b: Real): Bool = ctx.mkLe(a, b)
    def >(b: Real): Bool = ctx.mkGt(a, b)
    def >=(b: Real): Bool = ctx.mkGe(a, b)

  extension (a: BV)
    def +(b: BV): BV = ctx.mkBVAdd(a, b)
    def -(b: BV): BV = ctx.mkBVSub(a, b)
    def *(b: BV): BV = ctx.mkBVMul(a, b)
    def &(b: BV): BV = ctx.mkBVAND(a, b)
    def |(b: BV): BV = ctx.mkBVOR(a, b)

  extension [S <: Sort](a: Expr[S])
    def ===(b: Expr[S]): Bool = ctx.mkEq(a, b)
    def =/=(b: Expr[S]): Bool = ctx.mkDistinct(a, b)
