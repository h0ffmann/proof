# Z3 checks of chaceon, the Rust port of WAVEWATCH III: division rewrite, Fortran intrinsics, W3SRCE's
# time step, and how much of WW3 is translated and integrated (`z3-scala/z3.sh coverage`). Also in `just check`.
port-audit:
    bash checks/port-audit.sh

# Rewrite the coverage table of port-audit/README.md
port-audit-coverage:
    z3-scala/z3.sh coverage --write
