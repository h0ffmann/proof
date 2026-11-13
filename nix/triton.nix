# The Triton shell (`nix develop .#triton`): Python with Triton, PyTorch and NumPy, for
# ocean-triton/check.py, which runs the kernels that tools/ocean-triton/ prints from Agda. Every
# package comes from the nixpkgs that flake.lock pins; the versions below are written here so that
# a bump of the lock that moves one stops the evaluation.
{ pkgs }:
let
  tritonVersion = "3.7.1";
  torchVersion = "2.13.0";
  py = pkgs.python3.withPackages (ps:
    assert pkgs.lib.assertMsg (ps.triton.version == tritonVersion)
      "nix/triton.nix pins Triton ${tritonVersion}, the locked nixpkgs gives ${ps.triton.version}";
    assert pkgs.lib.assertMsg (ps.torch.version == torchVersion)
      "nix/triton.nix pins PyTorch ${torchVersion}, the locked nixpkgs gives ${ps.torch.version}";
    [ ps.triton ps.torch ps.numpy ]);
in
pkgs.mkShell {
  packages = [ py pkgs.just pkgs.git ];
  LANG = "C.UTF-8";
}
