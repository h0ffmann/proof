# Milestone M5: run WAVEWATCH III at the pin, capture W3SNL1, W3SBT1 and W3SDB1, and replay them
# through the Triton kernels printed from Agda, bit for bit (ww3-replay/README.md). Also in `just check`.
ww3-replay:
    bash checks/ww3-replay.sh

# Run WW3 again and write the captures into ww3-replay/captures/
ww3-replay-write:
    bash checks/ww3-replay.sh --write
