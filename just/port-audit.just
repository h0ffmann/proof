# Z3 checks of chaceon, the Rust port of WAVEWATCH III: division rewrite, Fortran intrinsics, W3SRCE's
# time step, and how much of WW3 is translated and integrated (port-audit/coverage.py). Also in `just check`.
port-audit:
    bash checks/port-audit.sh

# Rewrite the coverage table of port-audit/README.md
port-audit-coverage:
    python3 port-audit/coverage.py --write
