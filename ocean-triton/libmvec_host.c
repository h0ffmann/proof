/* What ocean-triton/libmvec.py needs from this machine and cannot compute in Python.
 *
 *     libmvec_host runs     each run of equal R = rint(rcpps(1.m x 2^-10)) over the 2^23
 *                           mantissas m, as "first-m R" lines: libmvec's SSE4 powf takes its
 *                           reciprocal from rcpps, whose bits are the CPU's, not IEEE's
 *     libmvec_host pow      float32 pairs (x, y) on stdin, _ZGVbN4vv_powf(x, y) on stdout
 *
 * The second is the reference of `python3 ocean-triton/libmvec.py --self-test`: the library
 * itself, called four lanes at a time as gfortran -O3 calls it from WW3.
 * SPDX-License-Identifier: MIT */
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <xmmintrin.h>

extern __m128 _ZGVbN4vv_powf(__m128, __m128);

int main(int argc, char **argv) {
  if (argc == 2 && strcmp(argv[1], "runs") == 0) {
    uint32_t last = 0;
    for (uint32_t m = 0; m < (1u << 23); ++m) {
      uint32_t u = 0x3a800000u | m;
      float in;
      memcpy(&in, &u, 4);
      uint32_t R = (uint32_t)nearbyint((double)_mm_cvtss_f32(_mm_rcp_ss(_mm_set_ss(in))));
      if (m == 0 || R != last) printf("%u %u\n", m, R);
      last = R;
    }
    return 0;
  }
  if (argc == 2 && strcmp(argv[1], "pow") == 0) {
    float in[8];
    size_t n;
    while ((n = fread(in, sizeof(float), 8, stdin)) > 0) {
      float a[4] = {1, 1, 1, 1}, b[4] = {1, 1, 1, 1}, r[4];
      for (size_t l = 0; 2 * l + 1 < n; ++l) { a[l] = in[2 * l]; b[l] = in[2 * l + 1]; }
      _mm_storeu_ps(r, _ZGVbN4vv_powf(_mm_loadu_ps(a), _mm_loadu_ps(b)));
      fwrite(r, sizeof(float), n / 2, stdout);
    }
    return 0;
  }
  fprintf(stderr, "usage: libmvec_host runs | pow\n");
  return 64;
}
