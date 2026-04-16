#!/usr/bin/env bash
set -euo pipefail
source "${1:-./config.sh}"
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS="${OMP_THREADS}"

ALIGN_DIR="${OUTDIR}/meta/bin_templates_affine"
META_DIR="${OUTDIR}/meta/meta_template_build"
mkdir -p "${META_DIR}" "${OUTDIR}/logs"

mapfile -t BIN_TMPS < <(awk -F, 'NR>1 {print $4}' "${ALIGN_DIR}/manifest.csv" | sed '/^$/d')
if [[ ${#BIN_TMPS[@]} -lt 2 ]]; then
  echo "Need at least two affinely aligned bin templates. Run step 2 first." >&2
  exit 1
fi

pushd "${META_DIR}" >/dev/null
${ANTS_MULTIVAR_TEMPLATE} \
  -d ${DIM} \
  -o "meta_" \
  -i 4 \
  -g 0.10 \
  -j "${TEMPLATE_BUILD_JOBS}" \
  -k 1 \
  -w 1 \
  -c "${TEMPLATE_BUILD_PARALLEL_MODE}" \
  -n 0 \
  -r 1 \
  -m "80x50x20x0" \
  -f "8x4x2x1" \
  -s "3x2x1x0vox" \
  -t "SyN" \
  "${BIN_TMPS[@]}" \
  2>&1 | tee "${OUTDIR}/logs/meta_template_build.log"
popd >/dev/null

META_TEMPLATE=$(ls "${META_DIR}/"meta_*template0.nii.gz 2>/dev/null | head -n 1)
if [[ -z "${META_TEMPLATE}" ]]; then
  echo "Meta-template not found after build." >&2
  exit 1
fi
cp -f "${META_TEMPLATE}" "${OUTDIR}/meta/meta_template_space.nii.gz"
echo "Meta-template: ${OUTDIR}/meta/meta_template_space.nii.gz"
