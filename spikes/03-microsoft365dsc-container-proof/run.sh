#!/usr/bin/env bash
# Convenience runner for the Linux Microsoft365DSC container proof.
#
# Builds the Linux + pwsh7 image and runs the no-credentials probes (R1/R2/R3/R4),
# writing results to ./results on the host. Pass a version to pin the release under
# test (recommended — see R9); defaults to 'latest', which the probes still record.
#
#   ./run.sh                 # test whatever the gallery serves now
#   ./run.sh 1.26.0          # pin an exact Microsoft365DSC release
#
# The Windows probes (R2 apply / R5 / R6 / R8) need a Windows container host; see
# README.md and Dockerfile.windows.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="${1:-latest}"
IMAGE="m365dsc-proof:linux"

echo "==> Building ${IMAGE} (Microsoft365DSC=${VERSION})"
docker build -f "${HERE}/Dockerfile.linux" \
  --build-arg "M365DSC_VERSION=${VERSION}" \
  -t "${IMAGE}" "${HERE}"

mkdir -p "${HERE}/results"
echo "==> Running probes (results -> ${HERE}/results)"
docker run --rm -v "${HERE}/results:/proof-results" "${IMAGE}"

echo "==> Done. See ${HERE}/results for the timestamped JSON + markdown."
