#!/usr/bin/env bash
# Download the California Housing data (Pace & Barry 1997, 1990 US census) as
# redistributed in ageron/handson-ml2 (Apache-2.0), pinned to one commit and
# checked against a SHA-256. Writes data/housing.csv (not committed).
set -euo pipefail
cd "$(dirname "$0")"
commit=7b7e23e7267356f8355580877eff98c43cda1bd0
sha=d4cd501af90475f09b814c7447c7701f59bf28e8cf1180205ae5ace9737a0109
url="https://raw.githubusercontent.com/ageron/handson-ml2/$commit/datasets/housing/housing.tgz"
[ -f housing.csv ] && { echo "data/housing.csv already there"; exit 0; }
curl -fsSL -o housing.tgz "$url"
echo "$sha  housing.tgz" | sha256sum -c -
tar xzf housing.tgz housing.csv
rm housing.tgz
wc -l housing.csv
