#!/usr/bin/env bash
# Executa cada arquivo do roteiro e escreve a saída em ../resultados.md.
# Python 3.11 ou mais novo, sem dependência. `linha_do_tempo.py` precisa do Manim e fica de fora.
set -euo pipefail
cd "$(dirname "$0")"
out=../resultados.md
{
  echo "# Saídas do código do roteiro"
  echo
  echo "Feito por \`codigo/rodar.sh\` em $(date -u +%Y-%m-%d), Python $(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')."
  for f in bandit.py nome.py teste_ab.py gancho_crenca.py ab_vs_bandit.py rsi_loop.py pi.py; do
    echo
    echo "## \`codigo/$f\`"
    echo
    echo '```text'
    python3 "$f"
    echo '```'
  done
} > "$out"
echo "escrito: $out"
