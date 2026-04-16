#!/usr/bin/env bash
set -euo pipefail
source "${1:-./config.sh}"
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS="${OMP_THREADS}"

ALIGN_DIR="${OUTDIR}/meta/bin_templates_affine"
mkdir -p "${ALIGN_DIR}" "${OUTDIR}/logs"

# Choose a mid-life anchor bin by center age.
BEST_BIN=""
BEST_DIST=9999
for BIN_DIR in "${OUTDIR}"/age_bins/*; do
  [[ -d "${BIN_DIR}" ]] || continue
  bin=$(basename "${BIN_DIR}")
  lo=${bin%%_*}
  hi=${bin##*_}
  center=$((10#${lo} + (10#${hi} - 10#${lo}) / 2))
  # Target center is the mid-point of overall age range.
  target_center=$(( BIN_START + (BIN_END - BIN_START) / 2 ))
  dist=$(( center > target_center ? center - target_center : target_center - center ))
  if (( dist < BEST_DIST )); then
    BEST_DIST=${dist}
    BEST_BIN=${bin}
  fi
done

if [[ -z "${BEST_BIN}" ]]; then
  echo "No age-bin template folders found. Run step 1 first." >&2
  exit 1
fi

echo "Anchor bin: ${BEST_BIN}"
ANCHOR_TEMPLATE=$(ls "${OUTDIR}/age_bins/${BEST_BIN}/template_build/"*template0.nii.gz 2>/dev/null | head -n 1)
if [[ -z "${ANCHOR_TEMPLATE}" ]]; then
  echo "Could not find anchor template image for ${BEST_BIN}" >&2
  exit 1
fi
cp -f "${ANCHOR_TEMPLATE}" "${ALIGN_DIR}/anchor_${BEST_BIN}.nii.gz"

echo "bin,template,affine_mat,warped_template,is_anchor" > "${ALIGN_DIR}/manifest.csv"

for BIN_DIR in "${OUTDIR}"/age_bins/*; do
  [[ -d "${BIN_DIR}" ]] || continue
  bin=$(basename "${BIN_DIR}")
  TEMPLATE=$(ls "${BIN_DIR}/template_build/"*template0.nii.gz 2>/dev/null | head -n 1)
  if [[ -z "${TEMPLATE}" ]]; then
    echo "[SKIP] missing template for ${bin}"
    continue
  fi

  if [[ "${bin}" == "${BEST_BIN}" ]]; then
    cp -f "${TEMPLATE}" "${ALIGN_DIR}/${bin}_to_anchor_affine.nii.gz"
    echo "${bin},${TEMPLATE},,${ALIGN_DIR}/${bin}_to_anchor_affine.nii.gz,1" >> "${ALIGN_DIR}/manifest.csv"
    continue
  fi

  outprefix="${ALIGN_DIR}/${bin}_to_anchor_"
  ${ANTS_REG} -d ${DIM} \
    -r ["${ANCHOR_TEMPLATE}","${TEMPLATE}",1] \
    -m ${AFFINE_METRIC}["${ANCHOR_TEMPLATE}","${TEMPLATE}",1,32,Regular,0.25] \
    -t Rigid[0.1] \
    -c [${AFFINE_ITERS},1e-8,10] \
    -s ${AFFINE_SMOOTH} \
    -f ${AFFINE_SHRINK} \
    -m ${AFFINE_METRIC}["${ANCHOR_TEMPLATE}","${TEMPLATE}",1,32,Regular,0.25] \
    -t Affine[0.1] \
    -c [${AFFINE_ITERS},1e-8,10] \
    -s ${AFFINE_SMOOTH} \
    -f ${AFFINE_SHRINK} \
    -o ["${outprefix}","${outprefix}Warped.nii.gz"] \
    2>&1 | tee "${OUTDIR}/logs/${bin}_affine_to_anchor.log"

  echo "${bin},${TEMPLATE},${outprefix}0GenericAffine.mat,${outprefix}Warped.nii.gz,0" >> "${ALIGN_DIR}/manifest.csv"
done
