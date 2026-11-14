"""One lane of glibc's libmvec _ZGVbN4vv_powf, its SSE4 build, in Triton, and the data it needs.

gfortran -O3 vectorises a loop of real powers four lanes at a time and calls libmvec for them
(the -O3 code of WW3 links _ZGVbN4vv_powf, `objdump -d`), and libmvec's powf is not glibc's
scalar powf: the two differ by a few ULP. W3SDS4's DDIAG (w3src4md.F90:2252) is such a loop, so
a kernel that means to give WW3's bits computes libmvec's algorithm there:

    log(x) from a reciprocal R of x's leading bits, rint(rcpps(1.m x 2^-10)), and a table of
    log(1/R) at R - 512; times y; then 2^(.) from a table of 2^(j/2048); in float64, every
    product rounded, and the result rounded once to float32. A lane that libmvec sends to
    scalar powf (x not a positive normal float below FLT_MAX, y infinite or NaN, |y log x|
    beyond the domain) takes `_pow` here.

The algorithm and its constants are glibc 2.44's sysdeps/x86_64/fpu/multiarch/
svml_s_powf4_core_sse4.S and svml_s_powf_data.S, as the owner's ww3-gpu wrote them down in
kokkos/tools/libm_bits/glibc_mathf.hpp (mvec_powf) and gen_tables.cpp at ff20ee9; nothing of
glibc's text is copied. The tables are not committed: `tables()` reads them from the libmvec.so.1
this process loads (the one WW3 links, in the Nix shell), checks the constants written below
against the library, and asks the CPU for rcpps (ocean-triton/libmvec_host.c), because rcpps
is an approximation whose bits are the vendor's.

    python3 ocean-triton/libmvec.py --self-test [N]

compares `vpowf` in the Triton interpreter with the library itself on N inputs (default 200000):
a spread of x and y, and the inputs of W3SDS4's DDIAG.
"""

import ctypes
import os
import struct
import subprocess
import sys
import tempfile

if __name__ == "__main__" and "--self-test" in sys.argv and "--device=cuda" not in sys.argv:
    os.environ["TRITON_INTERPRET"] = "1"  # before Triton is imported, which reads it then

import triton
import triton.language as tl

# Offsets in __svml_spow_data (glibc 2.44 sysdeps/x86_64/fpu/svml_s_powf_data.h): the log table
# of 520 doubles, the 2^(j/2048) table of 2048, and the size of the whole.
LOG_LA, LOG_END, EXP_T, SIZE = 8576, 12736, 13952, 30848
# The constants vpowf writes as literals, and where the library holds them.
EXPECT = [(0, 0x80800000, 4), (64, 0xfeffffff, 4), (128, 0x7f800000, 4), (12864, 0x3fd55555555543c5, 8),
          (12928, 0xbfdffffffffff81f, 8), (12992, 0x000fffffffffffff, 8), (13056, 0x3f50000000000000, 8),
          (13312, 0x3ff0000000000000, 8), (13568, 0x408ff80000000000, 8), (13632, 0x408ff00000000000, 8),
          (13696, 0x3fe62e42fefa39ef, 8), (30400, 0x40a71547652b82fe, 8), (30464, 0x4338000000000000, 8),
          (30528, 0x3fe0000000000000, 8), (30592, 0x3f362f3904051fa1, 8), (30656, 0x7ff, 8),
          (30720, 0x7fffffff, 4), (30784, 0x4059fe36, 4)]
# The layout of the table buffer every lane kernel takes as mv_ptr.
LA0: tl.constexpr = 1
T0: tl.constexpr = 521
S0: tl.constexpr = 2569


def _libmvec_path() -> str:
    ctypes.CDLL("libmvec.so.1")
    with open("/proc/self/maps", encoding="utf-8") as f:
        for line in f:
            p = line.split()[-1]
            if os.path.basename(p).startswith("libmvec.so"):
                return p
    raise RuntimeError("libmvec: libmvec.so.1 is not mapped")


def _symbol(data: bytes, name: str):
    """The file offset and size of a symbol of an ELF64 little-endian object, from .symtab."""
    shoff, = struct.unpack_from("<Q", data, 0x28)
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", data, 0x3A)
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
    raise RuntimeError(f"libmvec: no {name} in the symbol table")


def _host(*args, stdin=None) -> bytes:
    here = os.path.dirname(os.path.abspath(__file__))
    exe = os.path.join(tempfile.gettempdir(), f"ocean-triton-libmvec-host-{os.getuid()}")
    src = os.path.join(here, "libmvec_host.c")
    if not os.path.exists(exe) or os.path.getmtime(exe) < os.path.getmtime(src):
        subprocess.run(["cc", "-O2", "-o", exe, src, "-lmvec", "-lm"], check=True)
    return subprocess.run([exe, *args], input=stdin, capture_output=True, check=True).stdout


def tables() -> list:
    """The float64 buffer of vpowf: the number of rcpps runs, the log and exp2 tables, the
    first mantissa of each run and its R."""
    with open(_libmvec_path(), "rb") as f:
        lib = f.read()
    off, size = _symbol(lib, "__svml_spow_data")
    if size and size < SIZE:
        raise RuntimeError(f"libmvec: __svml_spow_data has {size} bytes, {SIZE} expected")
    d = lib[off:off + SIZE]
    for at, bits, width in EXPECT:
        got = int.from_bytes(d[at:at + width], "little")
        if got != bits:
            raise RuntimeError(f"libmvec: the constant at {at} is {got:#x}, {bits:#x} expected: another glibc")
    la = list(struct.unpack_from("<520d", d, LOG_LA))
    t = list(struct.unpack_from("<2048d", d, EXP_T))
    runs = [tuple(map(int, line.split())) for line in _host("runs").decode().splitlines()]
    if any(not 512 <= r <= 1031 for _, r in runs):
        raise RuntimeError("libmvec: rcpps gives an R outside the log table")
    return [float(len(runs))] + la + t + [float(m) for m, _ in runs] + [float(r) for _, r in runs]


@triton.jit
def _bits_to_f64(b):
    return b.to(tl.float64, bitcast=True)


@triton.jit
def _scalar_pow(x, y):
    y = tl.where(x == x, y, y)
    w = tl.exp(y.to(tl.float64) * tl.log(x.to(tl.float64))).to(tl.float32)
    return tl.where(y == 2.0, x * x, w)


@triton.jit
def vpowf(x, y, mv_ptr, z):
    """One lane of _ZGVbN4vv_powf (SSE4) for float32 x and y; z is an int32 zero per lane."""
    x = tl.where(z == 0, x, x)  # a scalar parameter becomes a float32 block
    y = tl.where(z == 0, y, y)
    xi = x.to(tl.int32, bitcast=True)
    yi = y.to(tl.int32, bitcast=True)
    # (int) (xi - 0x80800000) >= (int) 0xfeffffff, or |y| infinite or NaN: scalar powf.
    special = ((xi + 2139095040) >= -16777217) | ((yi & 0x7fffffff) >= 0x7f800000)
    xd = x.to(tl.float64)
    yd = y.to(tl.float64)
    xb = xd.to(tl.int64, bitcast=True)
    x1 = _bits_to_f64((xb & 0x000fffffffffffff) | 0x3f50000000000000)
    ed = (xb >> 52).to(tl.float64)
    m = (xi & 0x7fffff).to(tl.float64)
    # R: the last run whose first mantissa is at most m (the runs are in order of m).
    nr = tl.load(mv_ptr + z).to(tl.int32)
    lo = z
    hi = nr - 1
    for _ in range(16):
        mid = (lo + hi + 1) // 2
        ok = tl.load(mv_ptr + S0 + mid) <= m
        lo = tl.where(ok, mid, lo)
        hi = tl.where(ok, hi, mid - 1)
    R = tl.load(mv_ptr + S0 + nr + lo)
    q = x1 * R - 1.0
    bias = tl.where(R > 724.0, 1023.0, 1022.0)
    q2 = q * q
    # 0xbfdffffffffff81f, as a signed 64-bit integer.
    t = _bits_to_f64(z.to(tl.int64) + 0x3fd55555555543c5) * q + _bits_to_f64(z.to(tl.int64) - 0x40200000000007e1)
    t = t * q2
    qq = q + t
    s = tl.load(mv_ptr + LA0 + (R.to(tl.int32) - 512)) + qq
    v = (ed - bias) * _bits_to_f64(z.to(tl.int64) + 0x3fe62e42fefa39ef) + s
    v = v * yd
    top = (v.to(tl.int64, bitcast=True) >> 32) & 0x7fffffff
    special = special | (top > 0x4059fe36)
    shifter = _bits_to_f64(z.to(tl.int64) + 0x4338000000000000)
    w = _bits_to_f64(z.to(tl.int64) + 0x40a71547652b82fe) * v
    tt = (w - 0.5) + shifter
    k = tt - shifter
    f = (w - k) * _bits_to_f64(z.to(tl.int64) + 0x3f362f3904051fa1)
    tb = tt.to(tl.int64, bitcast=True)
    T = tl.load(mv_ptr + T0 + (tb & 0x7ff).to(tl.int32))
    res = T + f * T
    out = _bits_to_f64(res.to(tl.int64, bitcast=True) + ((tb >> 11) << 52)).to(tl.float32)
    return tl.where(special, _scalar_pow(x, y), out)


@triton.jit
def scalarf(x, y, mv_ptr, z):
    """glibc's scalar powf in vpowf's place: what checks/ww3-replay.sh's self-test prints, to see
    that WW3's bits tell the two apart."""
    return _scalar_pow(tl.where(z == 0, x, x), y)


@triton.jit
def _vpow_kernel(x_ptr, y_ptr, mv_ptr, out_ptr, n, BLOCK: tl.constexpr):
    i = tl.program_id(0) * BLOCK + tl.arange(0, BLOCK)
    msk = i < n
    z = i * 0
    x = tl.load(x_ptr + i, mask=msk, other=1.0)
    y = tl.load(y_ptr + i, mask=msk, other=1.0)
    tl.store(out_ptr + i, vpowf(x, y, mv_ptr, z), mask=msk)


def self_test(n: int) -> int:
    import random
    import torch
    rng = random.Random(1)
    xs, ys = [], []
    for j in range(n):
        if j % 4 == 0:   # W3SDS4's DDIAG: (B - BR)^SSDSP, B - BR of a few 1e-3, SSDSP = 2
            xs.append(rng.uniform(0.0, 0.02)); ys.append(2.0)
        elif j % 4 == 1:
            xs.append(10 ** rng.uniform(-30, 30)); ys.append(rng.uniform(-4, 4))
        elif j % 4 == 2:
            xs.append(rng.uniform(0.5, 2.0)); ys.append(rng.uniform(-60, 60))
        else:
            xs.append(rng.choice([0.0, 1.0, 2.0, float("inf"), 1e-40])); ys.append(rng.choice([2.0, 0.5, -1.0, 3.3]))
    f32 = lambda v: struct.unpack("<f", struct.pack("<f", v))[0]
    xs = [f32(v) for v in xs]; ys = [f32(v) for v in ys]
    ref = struct.unpack(f"<{n}f", _host("pow", stdin=struct.pack(f"<{2 * n}f", *[v for p in zip(xs, ys) for v in p])))
    mv = torch.tensor(tables(), dtype=torch.float64)
    out = torch.zeros(n, dtype=torch.float32)
    _vpow_kernel[((n + 4095) // 4096,)](torch.tensor(xs, dtype=torch.float32), torch.tensor(ys, dtype=torch.float32),
                                         mv, out, n, BLOCK=4096)
    got = out.tolist()
    same = lambda a, b: struct.pack("<f", a) == struct.pack("<f", b) or (a != a and b != b)
    bad = [(x, y, g, r) for x, y, g, r in zip(xs, ys, got, ref) if not same(g, r)]
    for x, y, g, r in bad[:10]:
        print(f"libmvec: powf({x!r}, {y!r}) = {r!r} in libmvec, {g!r} in vpowf")
    print(f"libmvec: {n - len(bad)}/{n} values of vpowf equal _ZGVbN4vv_powf's bits")
    return 1 if bad else 0


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "--self-test":
        sys.exit(self_test(int(sys.argv[2]) if len(sys.argv) > 2 else 200000))
    print(__doc__)
    sys.exit(64)
