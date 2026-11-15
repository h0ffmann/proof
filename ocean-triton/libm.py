"""glibc's float functions in Triton, as WAVEWATCH III's -O3 code calls them, with their bits.

A kernel that means to give WW3's bits has to compute WW3's libm, because glibc's expf, logf,
powf, sinf and cosf round to within about half an ULP but not always to the nearest float, and
libmvec's vector functions are other algorithms again. `objdump -dr` of w3src4md.F90.o at the
pin lists what ST4 calls: W3SIN4 atan2f, expf, log10f, logf, powf, sincosf and tanhf; W3SDS4 the
same and libmvec's _ZGVbN4vv_powf, _ZGVbN4v_expf, _cosf and _sinf; W3SPR4 _ZGVbN4vv_powf.

    expf, logf, powf    glibc 2.44's flt-32/e_expf.c, e_logf.c, e_powf.c (ARM's
                        optimized-routines): in float64 from small tables, rounded once
    sinf, cosf          glibc 2.44's s_sincosf.c, for |x| < 120 (a larger argument takes float64
                        cos and sin rounded, which is not glibc's reduction ⚠)
    tanhf, atan2f,      correctly rounded in glibc 2.44 (CORE-MATH); here float64, rounded once,
    log10f              which is the same float unless the value lies within about 1e-16 of a
                        midpoint ⚠. tanh and atan are Cephes' rational approximations (Moshier,
                        Cephes Math Library 2.8, tanh.c and atan.c), log10 is log / ln 10
    vpowf               one lane of libmvec's SSE4 _ZGVbN4vv_powf (svml_s_powf4_core_sse4.S)

On x86_64 glibc picks one build of expf, logf, powf and sincosf at load time: the one compiled
with -mfma when the CPU has FMA and AVX2, where GCC fused some a*b+c, else the SSE2 one. `madd`
reproduces either: fused, or a*b then +c. The fused sites and the algorithms are those the owner's
ww3-gpu read from the disassembly of __expf_fma, __logf_fma, __powf_fma and __sincosf_fma and
wrote down in kokkos/tools/libm_bits/glibc_mathf.hpp at ff20ee9 (with mvec_powf and its
gen_tables.cpp); nothing of glibc's text is copied. A fused multiply-add is emulated exactly in
float64 (Boldo and Melquiond, "Emulation of FMA and correctly rounded sums: proved algorithms
using rounding to odd", IEEE Trans. Computers 57(4), 2008, doi:10.1109/TC.2007.70819): the
interpreter's tl.fma rounds twice, and a GPU's real one would give the same bits as this.

The tables are not committed. `tables()` reads ARM's tables (__exp2f_data, __logf_data,
__powf_log2_data, __sincosf_table) from the libm.so.6 this process loads and libmvec's
(__svml_spow_data) from its libmvec.so.1, the libraries the Nix shell links WW3 against; checks
libmvec's constants against those written below; asks the CPU for rcpps
(ocean-triton/libmvec_host.c), whose bits are the vendor's; and reads whether glibc took its FMA
build from /proc/cpuinfo. Every kernel takes the buffer as lm_ptr and must be compiled without
contraction (enable_fp_fusion=False), as WW3 is.

    python3 ocean-triton/libm.py --self-test [N]

compares every function here, in Triton's interpreter, with the library itself on N inputs each
(default 100000): random arguments over their ranges, the edges, and W3SDS4's DDIAG for vpowf.
"""

import ctypes
import os
import struct
import subprocess
import sys
import tempfile

if __name__ == "__main__" and "--self-test" in sys.argv:
    os.environ["TRITON_INTERPRET"] = "1"  # before Triton is imported, which reads it then

import triton
import triton.language as tl

# The buffer, in float64 words: whether glibc took its FMA build, the number of rcpps runs,
# libmvec's log and 2^(j/2048) tables, ARM's four structures as glibc lays them out, then the
# first mantissa of each rcpps run and its R.
FMA: tl.constexpr = 0
NR: tl.constexpr = 1
LA: tl.constexpr = 2       # 520: log(1/R) for R = 512 … 1031
T: tl.constexpr = 522      # 2048
E2: tl.constexpr = 2570    # exp2f_data: tab[32], shift_scaled, poly[3], invln2_scaled, poly_scaled[3], shift
LG: tl.constexpr = 2611    # logf_data: tab[16] {invc, logc}, ln2, poly[3]
PW: tl.constexpr = 2647    # powf_log2_data: tab[16] {invc, logc}, poly[5]
SC: tl.constexpr = 2684    # sincosf_table[2]: sign[4], hpi_inv, hpi, c0, c1, s1, c2, s2, c3, s3, c4
RUNS: tl.constexpr = 2712
SIZES = {"__exp2f_data": 41, "__logf_data": 36, "__powf_log2_data": 37, "__sincosf_table": 28}

# __svml_spow_data (glibc 2.44 sysdeps/x86_64/fpu/svml_s_powf_data.h): the log table, the exp2
# table, the size, and every constant vpowf writes as a literal with its offset.
SPOW_LA, SPOW_T, SPOW_SIZE = 8576, 13952, 30848
SPOW_EXPECT = [(0, 0x80800000, 4), (64, 0xfeffffff, 4), (128, 0x7f800000, 4), (12864, 0x3fd55555555543c5, 8),
               (12928, 0xbfdffffffffff81f, 8), (12992, 0x000fffffffffffff, 8), (13056, 0x3f50000000000000, 8),
               (13312, 0x3ff0000000000000, 8), (13568, 0x408ff80000000000, 8), (13632, 0x408ff00000000000, 8),
               (13696, 0x3fe62e42fefa39ef, 8), (30400, 0x40a71547652b82fe, 8), (30464, 0x4338000000000000, 8),
               (30528, 0x3fe0000000000000, 8), (30592, 0x3f362f3904051fa1, 8), (30656, 0x7ff, 8),
               (30720, 0x7fffffff, 4), (30784, 0x4059fe36, 4)]


def _bits(v: float) -> int:
    """A float64's bits as a signed 64-bit integer, which Triton takes as an int64 literal."""
    return struct.unpack("<q", struct.pack("<d", v))[0]


# Float64 constants. A Python float in a kernel is a float32, so these enter as bits. The other
# way round is a trap too: a Python float beyond FLT_MAX (3.4028234664e38, one digit too many)
# is a float64, and a tl.where with it turns the whole expression around it into float64, which
# rounds once where the Fortran rounds at every step. Float32 edge values enter as bits
# (_f32), and every function returns a float32.
SPLIT: tl.constexpr = _bits(134217729.0)                 # 2^27 + 1, Dekker's split
INVLN10: tl.constexpr = _bits(0.43429448190325182765)
PIO2: tl.constexpr = _bits(1.57079632679489661923)
PIO4: tl.constexpr = _bits(0.78539816339744830962)
PI: tl.constexpr = _bits(3.14159265358979323846)
MOREBITS: tl.constexpr = _bits(6.123233995736765886130e-17)
HALF_MOREBITS: tl.constexpr = _bits(0.5 * 6.123233995736765886130e-17)
T3P8: tl.constexpr = _bits(2.41421356237309504880)
POW_OFLOW1: tl.constexpr = _bits(float.fromhex("0x1.fffffffa3aae2p+6"))
POW_OFLOW2: tl.constexpr = _bits(float.fromhex("0x1.fffffffd1d571p+6"))
# Cephes tanh.c, |x| < 0.625: tanh x = x + x^3 P(x^2) / Q(x^2).
TP0: tl.constexpr = _bits(-9.64399179425052238628e-1)
TP1: tl.constexpr = _bits(-9.92877231001918586564e1)
TP2: tl.constexpr = _bits(-1.61468768441708447952e3)
TQ0: tl.constexpr = _bits(1.12811678491632931402e2)
TQ1: tl.constexpr = _bits(2.23548839060100448583e3)
TQ2: tl.constexpr = _bits(4.84406305325125486048e3)
# Cephes atan.c: atan x = x + x^3 P(x^2) / Q(x^2) after the reduction to |x| <= 0.66.
AP0: tl.constexpr = _bits(-8.750608600031904122785e-1)
AP1: tl.constexpr = _bits(-1.615753718733365076637e1)
AP2: tl.constexpr = _bits(-7.500855792314704667340e1)
AP3: tl.constexpr = _bits(-1.228866684490136173410e2)
AP4: tl.constexpr = _bits(-6.485021904942025371773e1)
AQ0: tl.constexpr = _bits(2.485846490142306297962e1)
AQ1: tl.constexpr = _bits(1.650270098316988542046e2)
AQ2: tl.constexpr = _bits(4.328810604912902668951e2)
AQ3: tl.constexpr = _bits(4.853903996359136964868e2)
AQ4: tl.constexpr = _bits(1.945506571482613964425e2)


# --- the data -------------------------------------------------------------------------------

def _mapped(name: str) -> str:
    ctypes.CDLL(name)
    with open("/proc/self/maps", encoding="utf-8") as f:
        for line in f:
            p = line.split()[-1]
            if os.path.basename(p).startswith(name.split(".so")[0] + ".so"):
                return p
    raise RuntimeError(f"libm: {name} is not mapped")


def _symbol(data: bytes, name: str):
    """The file offset and size of a symbol of an ELF64 little-endian object, from .symtab."""
    shoff, = struct.unpack_from("<Q", data, 0x28)
    shentsize, shnum, _ = struct.unpack_from("<HHH", data, 0x3A)
    secs = [struct.unpack_from("<IIQQQQIIQQ", data, shoff + i * shentsize) for i in range(shnum)]
    for s in secs:
        if s[1] != 2:  # SHT_SYMTAB
            continue
        strtab = secs[s[6]]
        for j in range(s[5] // s[9]):
            nm, _info, _oth, shndx, value, size = struct.unpack_from("<IBBHQQ", data, s[4] + j * s[9])
            end = data.index(b"\0", strtab[4] + nm)
            if data[strtab[4] + nm:end] == name.encode():
                sec = secs[shndx]
                return value - sec[3] + sec[4], size
    raise RuntimeError(f"libm: no {name} in the symbol table")


def _host(*args, stdin=None) -> bytes:
    here = os.path.dirname(os.path.abspath(__file__))
    exe = os.path.join(tempfile.gettempdir(), f"ocean-triton-libmvec-host-{os.getuid()}")
    src = os.path.join(here, "libmvec_host.c")
    if not os.path.exists(exe) or os.path.getmtime(exe) < os.path.getmtime(src):
        subprocess.run(["cc", "-O2", "-o", exe, src, "-lmvec", "-lm"], check=True)
    return subprocess.run([exe, *args], input=stdin, capture_output=True, check=True).stdout


def host_fma() -> bool:
    """Whether glibc's ifunc takes the FMA build: the CPU has FMA and AVX2 (ifunc-fma.h)."""
    with open("/proc/cpuinfo", encoding="utf-8") as f:
        for line in f:
            if line.startswith("flags"):
                flags = line.split()
                return "fma" in flags and "avx2" in flags
    return False


def tables() -> list:
    """The float64 buffer every lane kernel takes as lm_ptr (the layout above)."""
    with open(_mapped("libmvec.so.1"), "rb") as f:
        mvec = f.read()
    off, size = _symbol(mvec, "__svml_spow_data")
    if size and size < SPOW_SIZE:
        raise RuntimeError(f"libm: __svml_spow_data has {size} bytes, {SPOW_SIZE} expected")
    d = mvec[off:off + SPOW_SIZE]
    for at, bits, width in SPOW_EXPECT:
        got = int.from_bytes(d[at:at + width], "little")
        if got != bits:
            raise RuntimeError(f"libm: libmvec's constant at {at} is {got:#x}, {bits:#x} expected: another glibc")
    with open(_mapped("libm.so.6"), "rb") as f:
        libm = f.read()
    arm = []
    for name, words in SIZES.items():
        o, s = _symbol(libm, name)
        if s != 8 * words:
            raise RuntimeError(f"libm: {name} has {s} bytes, {8 * words} expected: another glibc")
        arm += list(struct.unpack_from(f"<{words}d", libm, o))
    runs = [tuple(map(int, line.split())) for line in _host("runs").decode().splitlines()]
    if any(not 512 <= r <= 1031 for _, r in runs):
        raise RuntimeError("libm: rcpps gives an R outside libmvec's log table")
    buf = ([1.0 if host_fma() else 0.0, float(len(runs))] + list(struct.unpack_from("<520d", d, SPOW_LA))
           + list(struct.unpack_from("<2048d", d, SPOW_T)) + arm
           + [float(m) for m, _ in runs] + [float(r) for _, r in runs])
    assert len(buf) == RUNS + 2 * len(runs)
    return buf


# --- float64 helpers ------------------------------------------------------------------------

@triton.jit
def _f64(b):
    return b.to(tl.float64, bitcast=True)


@triton.jit
def _i64(x):
    return x.to(tl.int64, bitcast=True)


@triton.jit
def _u32(x):
    """A float32's bits as a non-negative int64."""
    return x.to(tl.int32, bitcast=True).to(tl.int64) & 0xffffffff


@triton.jit
def _f32(u):
    """The float32 whose bits are u (an int64 below 2^32)."""
    return u.to(tl.int32).to(tl.float32, bitcast=True)


@triton.jit
def _two_sum(a, b):
    s = a + b
    bb = s - a
    return s, (a - (s - bb)) + (b - bb)


@triton.jit
def _add_odd(a, b):
    """a + b rounded to odd: truncated, the last bit set when inexact."""
    s, e = _two_sum(a, b)
    sb = _i64(s)
    move = (e != 0.0) & ((sb & 1) == 0)
    up = (e > 0.0) == (s > 0.0)
    return _f64(tl.where(move, tl.where(up, sb + 1, sb - 1), sb))


@triton.jit
def _fma(a, b, c, zb):
    """a * b + c rounded once (Boldo and Melquiond's emulation; no overflow or underflow)."""
    sp = _f64(zb + SPLIT)
    ta = sp * a
    ah = ta - (ta - a)
    al = a - ah
    tb = sp * b
    bh = tb - (tb - b)
    bl = b - bh
    uh = a * b
    ul = ((ah * bh - uh) + ah * bl + al * bh) + al * bl
    th, tlo = _two_sum(c, uh)
    return th + _add_odd(tlo, ul)


@triton.jit
def _madd(a, b, c, fm, zb):
    """a * b + c as glibc's build computes it at a site GCC may fuse: fused when fm."""
    return tl.where(fm, _fma(a, b, c, zb), a * b + c)


@triton.jit
def _w(lm_ptr, at):
    return tl.load(lm_ptr + at)


# --- ARM's expf, logf, powf, sincosf --------------------------------------------------------

@triton.jit
def expf(x, lm_ptr, z):
    zb = z.to(tl.int64)
    fm = _w(lm_ptr, z + FMA) != 0.0
    x = tl.where(z == 0, x, x)
    ux = _u32(x)
    abstop = (ux >> 20) & 0x7ff
    xd = x.to(tl.float64)
    inv = _w(lm_ptr, z + (E2 + 36))
    shift = _w(lm_ptr, z + (E2 + 40))
    kd = _madd(inv, xd, shift, fm, zb)
    ki = _i64(kd)
    kd = kd - shift
    r = _madd(inv, xd, -kd, fm, zb)
    t = _i64(_w(lm_ptr, (E2 + (ki & 31)).to(tl.int32))) + (ki << 47)
    s = _f64(t)
    zz = _madd(_w(lm_ptr, z + (E2 + 37)), r, _w(lm_ptr, z + (E2 + 38)), fm, zb)
    r2 = r * r
    y = _madd(_w(lm_ptr, z + (E2 + 39)), r, 1.0 + zb.to(tl.float64), fm, zb)
    y = _madd(zz, r2, y, fm, zb)
    res = (y * s).to(tl.float32)
    big = abstop >= 0x42b
    res = tl.where(big & (x < -103.27892303466796875), _f32(zb + 1), res)  # may_uflowf: 2^-149
    res = tl.where(big & (x < -103.972076416015625), 0.0, res)
    res = tl.where(big & (x > 88.72283172607421875), float("inf"), res)
    res = tl.where(abstop >= 0x7f8, x + x, res)
    return tl.where(ux == 0xff800000, 0.0, res).to(tl.float32)


@triton.jit
def logf(x, lm_ptr, z):
    zb = z.to(tl.int64)
    fm = _w(lm_ptr, z + FMA) != 0.0
    x = tl.where(z == 0, x, x)
    ix = _u32(x)
    sub = (ix < 0x00800000) & (ix != 0)
    ix = tl.where(sub, (_u32(x * 8388608.0) - (23 << 23)) & 0xffffffff, ix)
    tmp = (ix - 0x3f330000) & 0xffffffff
    i = ((tmp >> 19) & 15).to(tl.int32)
    k = (tl.where(tmp >= 0x80000000, tmp - 0x100000000, tmp) >> 23).to(tl.float64)
    iz = (ix - (tmp & 0xff800000)) & 0xffffffff
    zz = _f32(iz).to(tl.float64)
    invc = _w(lm_ptr, LG + 2 * i)
    logc = _w(lm_ptr, LG + 2 * i + 1)
    r = _madd(zz, invc, -1.0 + zb.to(tl.float64), fm, zb)
    y0 = _madd(k, _w(lm_ptr, z + (LG + 32)), logc, fm, zb)
    r2 = r * r
    y = _madd(_w(lm_ptr, z + (LG + 34)), r, _w(lm_ptr, z + (LG + 35)), fm, zb)
    y = _madd(_w(lm_ptr, z + (LG + 33)), r2, y, fm, zb)
    y = _madd(y, r2, y0 + r, fm, zb)
    res = y.to(tl.float32)
    ix0 = _u32(x)
    res = tl.where(((ix0 & 0x80000000) != 0) | (ix0 > 0x7f800000), float("nan"), res)
    res = tl.where(ix0 == 0x7f800000, x, res)
    res = tl.where((ix0 & 0x7fffffff) == 0, float("-inf"), res)
    return tl.where(ix0 == 0x3f800000, 0.0, res).to(tl.float32)


@triton.jit
def _log2_inline(ix, lm_ptr, fm, zb):
    tmp = ix - 0x3f330000
    i = (((tmp & 0xffffffff) >> 19) & 15).to(tl.int32)
    top = (tmp & 0xffffffff) & 0xff800000
    iz = (ix - top) & 0xffffffff
    k = tl.where(top >= 0x80000000, top - 0x100000000, top) >> 23
    invc = _w(lm_ptr, PW + 2 * i)
    logc = _w(lm_ptr, PW + 2 * i + 1)
    zz = _f32(iz).to(tl.float64)
    r = _madd(zz, invc, -1.0 + zb.to(tl.float64), fm, zb)
    y0 = logc + k.to(tl.float64)
    r2 = r * r
    a0 = _w(lm_ptr, zb.to(tl.int32) + (PW + 32))
    a1 = _w(lm_ptr, zb.to(tl.int32) + (PW + 33))
    a2 = _w(lm_ptr, zb.to(tl.int32) + (PW + 34))
    a3 = _w(lm_ptr, zb.to(tl.int32) + (PW + 35))
    a4 = _w(lm_ptr, zb.to(tl.int32) + (PW + 36))
    y = _madd(a0, r, a1, fm, zb)
    p = _madd(a2, r, a3, fm, zb)
    r4 = r2 * r2
    q = _madd(a4, r, y0, fm, zb)
    q = _madd(p, r2, q, fm, zb)
    return _madd(y, r4, q, fm, zb)


@triton.jit
def _exp2_inline(xd, sign_bias, lm_ptr, fm, zb):
    z = zb.to(tl.int32)
    ss = _w(lm_ptr, z + (E2 + 32))
    kd = xd + ss
    ki = _i64(kd)
    kd = kd - ss
    r = xd - kd
    t = _i64(_w(lm_ptr, (E2 + (ki & 31)).to(tl.int32))) + ((ki + sign_bias) << 47)
    s = _f64(t)
    zz = _madd(_w(lm_ptr, z + (E2 + 33)), r, _w(lm_ptr, z + (E2 + 34)), fm, zb)
    r2 = r * r
    y = _madd(_w(lm_ptr, z + (E2 + 35)), r, 1.0 + zb.to(tl.float64), fm, zb)
    y = _madd(zz, r2, y, fm, zb)
    return y * s


@triton.jit
def _zeroinfnan(i):
    return ((2 * i - 1) & 0xffffffff) >= 0xfeffffff


@triton.jit
def _checkint(iy):
    """0: not an integer, 1: odd, 2: even (powf.c)."""
    e = (iy >> 23) & 0xff
    sh = tl.minimum(tl.maximum(0x96 - e, 0), 31)
    frac = (iy & ((tl.full(iy.shape, 1, tl.int64) << sh) - 1)) != 0
    odd = (iy & (tl.full(iy.shape, 1, tl.int64) << sh)) != 0
    return tl.where(e < 0x7f, 0, tl.where(e > 0x96, 2, tl.where(frac, 0, tl.where(odd, 1, 2))))


@triton.jit
def powf(x, y, lm_ptr, z):
    zb = z.to(tl.int64)
    fm = _w(lm_ptr, z + FMA) != 0.0
    x = tl.where(z == 0, x, x)
    y = tl.where(z == 0, y, y)
    ix = _u32(x)
    iy = _u32(y)
    neg = (ix & 0x80000000) != 0
    yint = _checkint(iy)
    sign_bias = tl.where(neg & (yint == 1), 65536, 0).to(tl.int64)
    ixm = ix & 0x7fffffff
    ixm = tl.where(ixm < 0x00800000, (_u32(tl.abs(x) * 8388608.0) & 0x7fffffff) - (23 << 23), ixm)
    ylogx = y.to(tl.float64) * _log2_inline(ixm, lm_ptr, fm, zb)
    res = _exp2_inline(ylogx, sign_bias, lm_ptr, fm, zb).to(tl.float32)
    sgn = sign_bias != 0
    big = ((_i64(ylogx) >> 47) & 0xffff) >= 0x80BF
    res = tl.where(big & (ylogx > _f64(zb + POW_OFLOW1)), tl.where(sgn, _f32(zb + 0xff7fffff), _f32(zb + 0x7f7fffff)), res)
    res = tl.where(big & (ylogx > _f64(zb + POW_OFLOW2)), tl.where(sgn, float("-inf"), float("inf")), res)
    res = tl.where(big & (ylogx < -149.0), tl.where(sgn, _f32(zb + 0x80000001), _f32(zb + 1)), res)
    res = tl.where(big & (ylogx <= -150.0), tl.where(sgn, _f32(zb + 0x80000000), 0.0), res)
    # A negative x with y not an integer.
    res = tl.where(neg & (yint == 0), float("nan"), res)
    # x zero, infinite or NaN (y not).
    x2 = tl.where(neg & (yint == 1), (x * x) * -1.0, x * x)
    zx = tl.where((iy & 0x80000000) != 0, 1.0 / x2, x2)
    zx = tl.where((((2 * ix) & 0xffffffff) == 0) & ((iy & 0x80000000) != 0),
                  tl.where(neg & (yint == 1), float("-inf"), float("inf")), zx)
    res = tl.where(_zeroinfnan(ix), zx, res)
    # y zero, infinite or NaN.
    zy = tl.where((((2 * ix) & 0xffffffff) < 0x7f000000) == ((iy & 0x80000000) == 0), 0.0, y * y)
    zy = tl.where(((2 * ix) & 0xffffffff) == 0x7f000000, 1.0, zy)
    zy = tl.where((((2 * ix) & 0xffffffff) > 0xff000000) | (((2 * iy) & 0xffffffff) > 0xff000000), x + y, zy)
    zy = tl.where(ix == 0x3f800000, 1.0, zy)
    zy = tl.where(((2 * iy) & 0xffffffff) == 0, 1.0, zy)
    return tl.where(_zeroinfnan(iy), zy, res).to(tl.float32)


@triton.jit
def _sincosf(y, lm_ptr, z):
    zb = z.to(tl.int64)
    fm = _w(lm_ptr, z + FMA) != 0.0
    y = tl.where(z == 0, y, y)
    uy = _u32(y)
    abstop = (uy >> 20) & 0x7ff
    x = y.to(tl.float64)
    small = abstop < 0x3f4
    r = x * _w(lm_ptr, z + (SC + 4))
    n = tl.where(small, 0, ((r.to(tl.int32) + 0x800000) >> 24))
    xr = _madd(-n.to(tl.float64), _w(lm_ptr, z + (SC + 5)), x, fm, zb)
    sg = _w(lm_ptr, SC + (n & 3))
    xs = tl.where(small, x, xr * sg)
    x2 = tl.where(small, x * x, xr * xr)
    p = SC + 14 * ((n >> 1) & 1)
    x4 = x2 * x2
    x3 = x2 * xs
    cc2 = _madd(x2, _w(lm_ptr, p + 13), _w(lm_ptr, p + 11), fm, zb)
    ss1 = _madd(x2, _w(lm_ptr, p + 12), _w(lm_ptr, p + 10), fm, zb)
    cc1 = _madd(x2, _w(lm_ptr, p + 7), _w(lm_ptr, p + 6), fm, zb)
    x5 = x3 * x2
    x6 = x4 * x2
    s = _madd(x3, _w(lm_ptr, p + 8), xs, fm, zb)
    c = _madd(x4, _w(lm_ptr, p + 9), cc1, fm, zb)
    sp = _madd(x5, ss1, s, fm, zb).to(tl.float32)
    cp = _madd(x6, cc2, c, fm, zb).to(tl.float32)
    odd = (n & 1) != 0
    sv = tl.where(odd, cp, sp)
    cv = tl.where(odd, sp, cp)
    tiny = abstop < 0x398
    sv = tl.where(tiny, y, sv)
    cv = tl.where(tiny, 1.0, cv)
    large = abstop >= 0x42f
    sv = tl.where(large, tl.sin(x).to(tl.float32), sv)
    cv = tl.where(large, tl.cos(x).to(tl.float32), cv)
    nf = abstop >= 0x7f8
    return tl.where(nf, y - y, sv).to(tl.float32), tl.where(nf, y - y, cv).to(tl.float32)


@triton.jit
def sinf(x, lm_ptr, z):
    s, c = _sincosf(x, lm_ptr, z)
    return s


@triton.jit
def cosf(x, lm_ptr, z):
    s, c = _sincosf(x, lm_ptr, z)
    return c


# --- the correctly rounded ones: float64, rounded once ---------------------------------------

@triton.jit
def tanhf(x, lm_ptr, z):
    zb = z.to(tl.int64)
    x = tl.where(z == 0, x, x)
    xd = x.to(tl.float64)
    ax = tl.abs(xd)
    w = xd * xd
    p = (_f64(zb + TP0) * w + _f64(zb + TP1)) * w + _f64(zb + TP2)
    q = ((w + _f64(zb + TQ0)) * w + _f64(zb + TQ1)) * w + _f64(zb + TQ2)
    small = xd + xd * w * (p / q)
    e = tl.exp(ax + ax)
    big = 1.0 - 2.0 / (e + 1.0)
    big = tl.where(xd < 0.0, -big, big)
    res = tl.where(ax < 0.625, small, tl.where(ax > 44.0, tl.where(xd < 0.0, -1.0, 1.0), big))
    return tl.where((x != x) | (x == 0.0), x, res.to(tl.float32)).to(tl.float32)


@triton.jit
def _atan64(t, zb):
    """atan of a float64 t, Cephes' atan.c."""
    a = tl.abs(t)
    hi = a > _f64(zb + T3P8)
    mid = (a > 0.66) & (~hi)
    xr = tl.where(hi, -1.0 / a, tl.where(mid, (a - 1.0) / (a + 1.0), a))
    y0 = tl.where(hi, _f64(zb + PIO2), tl.where(mid, _f64(zb + PIO4), 0.0 * a))
    w = xr * xr
    p = (((_f64(zb + AP0) * w + _f64(zb + AP1)) * w + _f64(zb + AP2)) * w + _f64(zb + AP3)) * w + _f64(zb + AP4)
    q = ((((w + _f64(zb + AQ0)) * w + _f64(zb + AQ1)) * w + _f64(zb + AQ2)) * w + _f64(zb + AQ3)) * w + _f64(zb + AQ4)
    v = xr * (w * p / q) + xr
    v = tl.where(hi, v + _f64(zb + MOREBITS), tl.where(mid, v + _f64(zb + HALF_MOREBITS), v))
    r = y0 + v
    return tl.where(_i64(t) < 0, r * -1.0, r)


@triton.jit
def atan2f(y, x, lm_ptr, z):
    zb = z.to(tl.int64)
    y = tl.where(z == 0, y, y)
    x = tl.where(z == 0, x, x)
    yd = y.to(tl.float64)
    xd = x.to(tl.float64)
    pi = _f64(zb + PI)
    # The sign of a zero counts, as in C's atan2: x < 0 or x = -0 turns the result by pi.
    xneg = (_u32(x) & 0x80000000) != 0
    yneg = (_u32(y) & 0x80000000) != 0
    a = _atan64(yd / xd, zb)
    r = tl.where(xneg, tl.where(yneg, a - pi, a + pi), a)
    hp = _f64(zb + PIO2)
    r = tl.where(xd == 0.0, tl.where(yneg, -hp, hp), r)
    zr = tl.where(xneg, tl.where(yneg, -pi, pi), yd)
    r = tl.where(yd == 0.0, zr, r)
    # Infinities: the limits of the directions.
    xinf = tl.abs(xd) == float("inf")
    yinf = tl.abs(yd) == float("inf")
    sy = tl.where(yneg, -1.0, 1.0)
    r = tl.where(xinf & ~yinf, tl.where(xneg, sy * pi, yd * 0.0), r)
    r = tl.where(yinf & ~xinf, sy * hp, r)
    r = tl.where(xinf & yinf, sy * tl.where(xneg, pi * 0.75, pi * 0.25), r)
    res = r.to(tl.float32)
    return tl.where((x != x) | (y != y), x + y, res).to(tl.float32)


@triton.jit
def log10f(x, lm_ptr, z):
    zb = z.to(tl.int64)
    x = tl.where(z == 0, x, x)
    r = (tl.log(x.to(tl.float64)) * _f64(zb + INVLN10)).to(tl.float32)
    return tl.where(x == 1.0, 0.0, r).to(tl.float32)


# --- libmvec's _ZGVbN4vv_powf, one lane ------------------------------------------------------

@triton.jit
def vpowf(x, y, lm_ptr, z):
    """One lane of _ZGVbN4vv_powf (SSE4): log(x) from R = rint(rcpps(1.m 2^-10)) and a table,
    times y, then 2^(.) from a 2^11-entry table, in float64 with every product rounded; a lane
    the library sends to scalar powf takes `powf`."""
    zb = z.to(tl.int64)
    x = tl.where(z == 0, x, x)
    y = tl.where(z == 0, y, y)
    xi = x.to(tl.int32, bitcast=True)
    yi = y.to(tl.int32, bitcast=True)
    # (int) (xi - 0x80800000) >= (int) 0xfeffffff, or |y| infinite or NaN.
    special = ((xi + 2139095040) >= -16777217) | ((yi & 0x7fffffff) >= 0x7f800000)
    xd = x.to(tl.float64)
    yd = y.to(tl.float64)
    xb = _i64(xd)
    x1 = _f64((xb & 0x000fffffffffffff) | 0x3f50000000000000)
    ed = (xb >> 52).to(tl.float64)
    m = (xi & 0x7fffff).to(tl.float64)
    # R: the last rcpps run whose first mantissa is at most m.
    nr = _w(lm_ptr, z + NR).to(tl.int32)
    lo = z
    hi = nr - 1
    for _ in range(16):
        mid = (lo + hi + 1) // 2
        ok = _w(lm_ptr, RUNS + mid) <= m
        lo = tl.where(ok, mid, lo)
        hi = tl.where(ok, hi, mid - 1)
    R = _w(lm_ptr, RUNS + nr + lo)
    q = x1 * R - 1.0
    bias = tl.where(R > 724.0, 1023.0, 1022.0)
    q2 = q * q
    # 0xbfdffffffffff81f as a signed 64-bit integer.
    t = _f64(zb + 0x3fd55555555543c5) * q + _f64(zb - 0x40200000000007e1)
    t = t * q2
    qq = q + t
    s = _w(lm_ptr, LA + (R.to(tl.int32) - 512)) + qq
    v = (ed - bias) * _f64(zb + 0x3fe62e42fefa39ef) + s
    v = v * yd
    top = (_i64(v) >> 32) & 0x7fffffff
    special = special | (top > 0x4059fe36)
    shifter = _f64(zb + 0x4338000000000000)
    w = _f64(zb + 0x40a71547652b82fe) * v
    tt = (w - 0.5) + shifter
    k = tt - shifter
    f = (w - k) * _f64(zb + 0x3f362f3904051fa1)
    tb = _i64(tt)
    Tj = _w(lm_ptr, T + (tb & 0x7ff).to(tl.int32))
    res = Tj + f * Tj
    out = _f64(_i64(res) + ((tb >> 11) << 52)).to(tl.float32)
    return tl.where(special, powf(x, y, lm_ptr, z), out).to(tl.float32)


# --- the self-test --------------------------------------------------------------------------

@triton.jit
def _kernel1(x_ptr, lm_ptr, out_ptr, n, WHICH: tl.constexpr, BLOCK: tl.constexpr):
    i = tl.program_id(0) * BLOCK + tl.arange(0, BLOCK)
    msk = i < n
    z = i * 0
    x = tl.load(x_ptr + i, mask=msk, other=1.0)
    if WHICH == 0:
        r = expf(x, lm_ptr, z)
    elif WHICH == 1:
        r = logf(x, lm_ptr, z)
    elif WHICH == 2:
        r = sinf(x, lm_ptr, z)
    elif WHICH == 3:
        r = cosf(x, lm_ptr, z)
    elif WHICH == 4:
        r = tanhf(x, lm_ptr, z)
    else:
        r = log10f(x, lm_ptr, z)
    tl.store(out_ptr + i, r, mask=msk)


@triton.jit
def _kernel2(x_ptr, y_ptr, lm_ptr, out_ptr, n, WHICH: tl.constexpr, BLOCK: tl.constexpr):
    i = tl.program_id(0) * BLOCK + tl.arange(0, BLOCK)
    msk = i < n
    z = i * 0
    x = tl.load(x_ptr + i, mask=msk, other=1.0)
    y = tl.load(y_ptr + i, mask=msk, other=1.0)
    if WHICH == 0:
        r = powf(x, y, lm_ptr, z)
    elif WHICH == 1:
        r = atan2f(x, y, lm_ptr, z)
    else:
        r = vpowf(x, y, lm_ptr, z)
    tl.store(out_ptr + i, r, mask=msk)


@triton.jit
def scalarf(x, y, lm_ptr, z):
    """powf in vpowf's place: what checks/ww3-replay.sh's self-test prints, to see that WW3's
    bits tell the two apart."""
    return powf(x, y, lm_ptr, z)


def self_test(n: int) -> int:
    import math
    import random
    import warnings
    import torch
    warnings.filterwarnings("ignore", category=RuntimeWarning)
    rng = random.Random(1)
    f32 = lambda v: struct.unpack("<f", struct.pack("<f", v))[0]
    same = lambda a, b: struct.pack("<f", a) == struct.pack("<f", b) or (a != a and b != b)
    lib = ctypes.CDLL("libm.so.6")
    mv = torch.tensor(tables(), dtype=torch.float64)
    edges = [0.0, -0.0, 1.0, -1.0, float("inf"), float("-inf"), float("nan"), 1e-45, 1e-40, -1e-40, 2.0, 0.5,
             88.72283172607421875, 88.7228393554, -103.27892303466796875, -103.5, -104.0, 1e-8, 119.9, 3e38]
    unary = [
        (0, "expf", lambda: rng.uniform(-110, 95)),
        (1, "logf", lambda: 10 ** rng.uniform(-44, 38)),
        (2, "sinf", lambda: rng.uniform(-120, 120) if rng.random() < 0.8 else rng.uniform(-1, 1)),
        (3, "cosf", lambda: rng.uniform(-120, 120) if rng.random() < 0.8 else rng.uniform(-1, 1)),
        (4, "tanhf", lambda: rng.uniform(-12, 12) if rng.random() < 0.7 else 10 ** rng.uniform(-30, 0)),
        (5, "log10f", lambda: 10 ** rng.uniform(-44, 38)),
    ]
    bad_total = 0
    for which, name, gen in unary:
        xs = [f32(v) for v in edges] + [f32(gen()) for _ in range(n)]
        cf = getattr(lib, name)
        cf.restype = ctypes.c_float
        cf.argtypes = [ctypes.c_float]
        ref = [cf(v) for v in xs]
        out = torch.zeros(len(xs), dtype=torch.float32)
        _kernel1[((len(xs) + 4095) // 4096,)](torch.tensor(xs, dtype=torch.float32), mv, out, len(xs),
                                              WHICH=which, BLOCK=4096)
        bad = [(x, g, r) for x, g, r in zip(xs, out.tolist(), ref) if not same(g, r)]
        for x, g, r in bad[:5]:
            print(f"libm: {name}({x!r}) = {r!r} in glibc, {g!r} here")
        print(f"libm: {len(xs) - len(bad)}/{len(xs)} values of {name} equal glibc's bits")
        bad_total += len(bad)
    pairs = [
        (0, "powf", lambda: (10 ** rng.uniform(-20, 20), rng.uniform(-6, 6)) if rng.random() < 0.6
         else (rng.uniform(0, 0.02), 2.0) if rng.random() < 0.5 else (rng.uniform(-3, 3), float(rng.randint(-5, 5)))),
        (1, "atan2f", lambda: (rng.uniform(-2, 2), rng.uniform(-2, 2)) if rng.random() < 0.8
         else (10 ** rng.uniform(-30, 30) * rng.choice([-1, 1]), 10 ** rng.uniform(-30, 30) * rng.choice([-1, 1]))),
        (2, "vpowf", lambda: (rng.uniform(0.0, 0.02), 2.0) if rng.random() < 0.3
         else (10 ** rng.uniform(-30, 30), rng.uniform(-4, 4)) if rng.random() < 0.5
         else (rng.uniform(0.5, 2.0), rng.uniform(-60, 60))),
    ]
    for which, name, gen in pairs:
        ps = [(f32(a), f32(b)) for a in edges[:12] for b in edges[:12]] + [tuple(f32(v) for v in gen()) for _ in range(n)]
        if name == "vpowf":
            ref = struct.unpack(f"<{len(ps)}f", _host("pow", stdin=struct.pack(f"<{2 * len(ps)}f", *[v for p in ps for v in p])))
        else:
            cf = getattr(lib, name)
            cf.restype = ctypes.c_float
            cf.argtypes = [ctypes.c_float, ctypes.c_float]
            ref = [cf(a, b) for a, b in ps]
        out = torch.zeros(len(ps), dtype=torch.float32)
        _kernel2[((len(ps) + 4095) // 4096,)](torch.tensor([a for a, _ in ps], dtype=torch.float32),
                                              torch.tensor([b for _, b in ps], dtype=torch.float32),
                                              mv, out, len(ps), WHICH=which, BLOCK=4096)
        bad = [(p, g, r) for p, g, r in zip(ps, out.tolist(), ref) if not same(g, r)]
        for p, g, r in bad[:5]:
            print(f"libm: {name}{p!r} = {r!r} in glibc, {g!r} here")
        print(f"libm: {len(ps) - len(bad)}/{len(ps)} values of {name} equal glibc's bits")
        bad_total += len(bad)
    print(f"libm: glibc's {'FMA' if host_fma() else 'SSE2'} build; "
          f"{'all agree' if bad_total == 0 else f'{bad_total} differ'}")
    return 1 if bad_total else 0


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "--self-test":
        sys.exit(self_test(int(sys.argv[2]) if len(sys.argv) > 2 else 100000))
    print(__doc__)
    sys.exit(64)
