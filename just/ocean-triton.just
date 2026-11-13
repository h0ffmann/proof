# The ocean-wave kernels as Triton kernels, printed from Agda (ocean-triton/README.md): the files
# are current, and Triton (CPU interpreter) agrees with the exact values. Also in `just check`.
ocean-triton:
    bash checks/ocean-triton.sh

# Print ocean-triton/kernels.py and ocean-triton/vectors.json again from agda/src/OceanTriton/
ocean-triton-write:
    bash checks/ocean-triton.sh --write

# Run the printed kernels on a CUDA GPU (needs one, and a Triton that sees it)
ocean-triton-cuda:
    nix develop --no-update-lock-file .#triton --command python3 ocean-triton/check.py ocean-triton/kernels.py ocean-triton/vectors.json --device cuda
