# Z3 checks of chaceon, the Rust port of WAVEWATCH III: division rewrite, Fortran intrinsics, W3SRCE's
# time step. port-audit/README.md lists what Z3 cannot prove there. Also in `just check`.
port-audit:
    bash checks/port-audit.sh
