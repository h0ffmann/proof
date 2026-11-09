# The graph shell (`nix develop .#graph`, then `just graph` or `just render-graph`): graphify
# 0.9.100 (pip's graphifyy, the version AGENTS.md names) for graphs/*/, and Node with Playwright and
# Chromium for graphs/triad/render.mjs. render.mjs takes Chromium from CHROMIUM, set here on Linux;
# nixpkgs builds Chromium for Linux only, so on macOS Playwright looks for its own browser.
# graph.html loads vis-network 9.1.6 from unpkg; VIS_NETWORK serves the same file from the store,
# so the render needs no network.
{ pkgs }:
let
  py = pkgs.python3.pkgs;
  graphify = py.buildPythonApplication rec {
    pname = "graphifyy";
    version = "0.9.100";
    format = "wheel";
    src = py.fetchPypi {
      inherit pname version format;
      dist = "py3";
      python = "py3";
      hash = "sha256-ZMXtby3MjCi2qWyHAjhRwWRMFvVah/RdvJEnEZ6252k=";
    };
    # What `graphify export html` uses. The tree-sitter grammars serve the code scanner, which
    # nothing here runs, so they are left out and the wheel's list of them is not enforced.
    dependencies = [ py.networkx py.numpy py.rapidfuzz py.pyyaml ];
    dontCheckRuntimeDeps = true;
  };
  # render.mjs does require("playwright"); nixpkgs ships the same module as playwright-core.
  nodeModules = pkgs.runCommand "graph-node-modules" { } ''
    mkdir -p $out
    ln -s ${pkgs.playwright-driver} $out/playwright
  '';
  visNetwork = pkgs.fetchurl {
    url = "https://registry.npmjs.org/vis-network/-/vis-network-9.1.6.tgz";
    hash = "sha256-4fO0L2ycjOJZao40PbP0cBL+Kyxpg/pgtBqXaih9oLI=";
  };
  visNetworkJs = pkgs.runCommand "vis-network-9.1.6.min.js" { } ''
    tar -xzf ${visNetwork} package/standalone/umd/vis-network.min.js
    cp package/standalone/umd/vis-network.min.js $out
  '';
in
pkgs.mkShell ({
  packages = [ graphify pkgs.python3 pkgs.nodejs_22 pkgs.just ]
    ++ pkgs.lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.chromium;
  NODE_PATH = "${nodeModules}";
  VIS_NETWORK = "${visNetworkJs}";
} // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
  CHROMIUM = "${pkgs.chromium}/bin/chromium";
})
