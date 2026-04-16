#!/usr/bin/env bash
set -euo pipefail
source "${1:-./config.sh}"
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS="${OMP_THREADS}"

META_TEMPLATE="${OUTDIR}/meta/meta_template_space.nii.gz"
ALIGN_DIR="${OUTDIR}/meta/bin_templates_affine"
BIN2META_DIR="${OUTDIR}/meta/bin_to_meta"
mkdir -p "${BIN2META_DIR}" "${OUTDIR}/logs"

if [[ ! -f "${META_TEMPLATE}" ]]; then
  echo "Meta-template not found. Run step 3 first." >&2
  exit 1
fi

echo "bin,bin_template_affine,warp,affine,warped" > "${BIN2META_DIR}/manifest.csv"
while IFS=, read -r bin template affine_mat warped_template is_anchor; do
  [[ "${bin}" == "bin" ]] && continue
  outprefix="${BIN2META_DIR}/${bin}_to_meta_"
  ${ANTS_REG} -d ${DIM} \
    -r ["${META_TEMPLATE}","${warped_template}",1] \
    -m ${AFFINE_METRIC}["${META_TEMPLATE}","${warped_template}",1,32,Regular,0.25] \
    -t Rigid[0.1] \
    -c [${AFFINE_ITERS},1e-8,10] \
    -s ${AFFINE_SMOOTH} \
    -f ${AFFINE_SHRINK} \
    -m ${AFFINE_METRIC}["${META_TEMPLATE}","${warped_template}",1,32,Regular,0.25] \
    -t Affine[0.1] \
    -c [${AFFINE_ITERS},1e-8,10] \
    -s ${AFFINE_SMOOTH} \
    -f ${AFFINE_SHRINK} \
    -m CC["${META_TEMPLATE}","${warped_template}",1,4] \
    -t SyN[0.10,3,0] \
    -c [80x50x20x0,1e-7,8] \
    -s 3x2x1x0vox \
    -f 8x4x2x1 \
    -o ["${outprefix}","${outprefix}Warped.nii.gz"] \
    2>&1 | tee "${OUTDIR}/logs/${bin}_to_meta.log"

  echo "${bin},${warped_template},${outprefix}1Warp.nii.gz,${outprefix}0GenericAffine.mat,${outprefix}Warped.nii.gz" >> "${BIN2META_DIR}/manifest.csv"
done < "${ALIGN_DIR}/manifest.csv"
