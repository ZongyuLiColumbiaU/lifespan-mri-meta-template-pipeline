#!/usr/bin/env bash
set -euo pipefail

source "${1:-./config.sh}"
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS="${OMP_THREADS}"

META_TEMPLATE="${OUTDIR}/meta/meta_template_space.nii.gz"
SUBJ_TABLE="${OUTDIR}/meta/all_subjects_with_bins.csv"
BIN2META_MANIFEST="${OUTDIR}/meta/bin_to_meta/manifest.csv"
OUT_SUBJ_DIR="${OUTDIR}/subjects_to_meta"
LOG_DIR="${OUTDIR}/logs"
CREATE_JD_TOOL="${CREATE_JACOBIAN:-CreateJacobianDeterminantImage}"
JAC_GEOM="${JACOBIAN_USE_GEOMETRIC:-1}"

mkdir -p "${OUT_SUBJ_DIR}" "${LOG_DIR}"

if [[ ! -f "${META_TEMPLATE}" ]]; then
  echo "Meta-template not found: ${META_TEMPLATE}. Run steps 3 and 4 first." >&2
  exit 1
fi

if [[ ! -f "${SUBJ_TABLE}" ]]; then
  echo "Subject table not found: ${SUBJ_TABLE}. Run step 0 first." >&2
  exit 1
fi

if [[ ! -f "${BIN2META_MANIFEST}" ]]; then
  echo "Bin->meta manifest not found: ${BIN2META_MANIFEST}. Run step 4 first." >&2
  exit 1
fi

if ! command -v "${ANTS_REG}" >/dev/null 2>&1; then
  echo "antsRegistration not found: ${ANTS_REG}" >&2
  exit 1
fi

if ! command -v "${ANTS_APPLY}" >/dev/null 2>&1; then
  echo "antsApplyTransforms not found: ${ANTS_APPLY}" >&2
  exit 1
fi

if ! command -v "${CREATE_JD_TOOL}" >/dev/null 2>&1; then
  echo "CreateJacobianDeterminantImage not found: ${CREATE_JD_TOOL}" >&2
  exit 1
fi

# Helper: pull bin->meta transforms for a given bin label.
get_bin2meta_row() {
  local bin="$1"
  awk -F, -v b="$bin" 'NR>1 && $1==b {print $0}' "${BIN2META_MANIFEST}"
}

MANIFEST="${OUT_SUBJ_DIR}/manifest.csv"
echo "subject_id,age,t1_brain,bin_label,bin_template,subj_to_bin_warp,subj_to_bin_inverse_warp,subj_to_bin_affine,subj_in_bin_t1,subj_to_bin_jd,subj_to_bin_logjd,bin_to_meta_warp,bin_to_meta_affine,subj_to_meta_composite_warp,subj_in_meta_t1,subj_to_meta_jd,subj_to_meta_logjd" > "${MANIFEST}"

while IFS=, read -r subject_id age t1_brain bin_lo bin_hi nearest_bin_lo nearest_bin_hi; do
  [[ "${subject_id}" == "subject_id" ]] && continue

  BIN_LABEL=$(printf "%02d_%02d" "${nearest_bin_lo}" "${nearest_bin_hi}")
  BIN_TEMPLATE=$(ls "${OUTDIR}/age_bins/${BIN_LABEL}/template_build/"*template0.nii.gz 2>/dev/null | head -n 1)
  if [[ -z "${BIN_TEMPLATE}" ]]; then
    echo "[SKIP] ${subject_id}: missing bin template ${BIN_LABEL}" >&2
    continue
  fi

  bin2meta_row=$(get_bin2meta_row "${BIN_LABEL}")
  if [[ -z "${bin2meta_row}" ]]; then
    echo "[SKIP] ${subject_id}: missing bin->meta transforms for ${BIN_LABEL}" >&2
    continue
  fi

  IFS=, read -r _bin _template_affine BIN2META_WARP BIN2META_AFFINE BIN2META_WARPED <<< "${bin2meta_row}"

  SUBJ_DIR="${OUT_SUBJ_DIR}/${subject_id}"
  mkdir -p "${SUBJ_DIR}"

  REG_PREFIX="${SUBJ_DIR}/${subject_id}_to_${BIN_LABEL}_"
  SUBJ_IN_BIN="${SUBJ_DIR}/${subject_id}_in_${BIN_LABEL}.nii.gz"
  SUBJ2BIN_JD="${SUBJ_DIR}/${subject_id}_jd_in_${BIN_LABEL}.nii.gz"
  SUBJ2BIN_LOGJD="${SUBJ_DIR}/${subject_id}_logjd_in_${BIN_LABEL}.nii.gz"

  META_COMPOSITE_WARP="${SUBJ_DIR}/${subject_id}_to_meta_composite_displacement.nii.gz"
  SUBJ_IN_META="${SUBJ_DIR}/${subject_id}_in_meta.nii.gz"
  SUBJ2META_JD="${SUBJ_DIR}/${subject_id}_jd_in_meta.nii.gz"
  SUBJ2META_LOGJD="${SUBJ_DIR}/${subject_id}_logjd_in_meta.nii.gz"

  # ------------------------------------------------------------
  # Subject -> nearest age-bin template registration
  # Fixed  = age-bin template
  # Moving = subject T1 brain
  # ------------------------------------------------------------
  "${ANTS_REG}" -d "${DIM}" \
    -r ["${BIN_TEMPLATE}","${t1_brain}",1] \
    -m ${SUBJ_TO_BIN_METRIC_LINEAR}["${BIN_TEMPLATE}","${t1_brain}",1,32,Regular,0.25] \
    -t Rigid[0.1] \
    -c [${SUBJ_TO_BIN_ITERS_LINEAR},1e-8,10] \
    -s ${SUBJ_TO_BIN_SMOOTH} \
    -f ${SUBJ_TO_BIN_SHRINK} \
    -m ${SUBJ_TO_BIN_METRIC_LINEAR}["${BIN_TEMPLATE}","${t1_brain}",1,32,Regular,0.25] \
    -t Affine[0.1] \
    -c [${SUBJ_TO_BIN_ITERS_LINEAR},1e-8,10] \
    -s ${SUBJ_TO_BIN_SMOOTH} \
    -f ${SUBJ_TO_BIN_SHRINK} \
    -m ${SUBJ_TO_BIN_METRIC_SYN}["${BIN_TEMPLATE}","${t1_brain}",1,4] \
    -t ${SUBJ_TO_BIN_SYN} \
    -c [${SUBJ_TO_BIN_ITERS_SYN},1e-7,8] \
    -s ${SUBJ_TO_BIN_SMOOTH} \
    -f ${SUBJ_TO_BIN_SHRINK} \
    -o ["${REG_PREFIX}","${SUBJ_IN_BIN}"] \
    2>&1 | tee "${LOG_DIR}/${subject_id}_to_${BIN_LABEL}.log"

  if [[ ! -f "${REG_PREFIX}1Warp.nii.gz" || ! -f "${REG_PREFIX}0GenericAffine.mat" ]]; then
    echo "[SKIP] ${subject_id}: registration did not produce expected forward transforms" >&2
    continue
  fi

  # ------------------------------------------------------------
  # TBM map in age-bin space
  # Domain = age-bin template (fixed image domain)
  # This is the Jacobian of the subject->bin forward displacement field.
  # ------------------------------------------------------------
  "${CREATE_JD_TOOL}" "${DIM}" "${REG_PREFIX}1Warp.nii.gz" "${SUBJ2BIN_JD}" 0 "${JAC_GEOM}"
  "${CREATE_JD_TOOL}" "${DIM}" "${REG_PREFIX}1Warp.nii.gz" "${SUBJ2BIN_LOGJD}" 1 "${JAC_GEOM}"

  # ------------------------------------------------------------
  # Compose subject -> bin -> meta as a displacement field in meta space.
  # Requires ANTs >= 2.6.0 for direct composite output from antsApplyTransforms.
  # ------------------------------------------------------------
  "${ANTS_APPLY}" -d "${DIM}" \
    -r "${META_TEMPLATE}" \
    -o ["${META_COMPOSITE_WARP}",1] \
    -t "${BIN2META_WARP}" \
    -t "${BIN2META_AFFINE}" \
    -t "${REG_PREFIX}1Warp.nii.gz" \
    -t "${REG_PREFIX}0GenericAffine.mat" \
    > "${LOG_DIR}/${subject_id}_compose_to_meta.log" 2>&1

  if [[ ! -f "${META_COMPOSITE_WARP}" ]]; then
    echo "[SKIP] ${subject_id}: failed to create subject->meta composite displacement field" >&2
    continue
  fi

  # Warp subject T1 into meta space.
  "${ANTS_APPLY}" -d "${DIM}" \
    -i "${t1_brain}" \
    -r "${META_TEMPLATE}" \
    -o "${SUBJ_IN_META}" \
    -n Linear \
    -t "${META_COMPOSITE_WARP}"

  # ------------------------------------------------------------
  # Integrated TBM map in meta space
  # Domain = meta-template
  # This Jacobian comes from the composed subject->meta displacement field.
  # ------------------------------------------------------------
  "${CREATE_JD_TOOL}" "${DIM}" "${META_COMPOSITE_WARP}" "${SUBJ2META_JD}" 0 "${JAC_GEOM}"
  "${CREATE_JD_TOOL}" "${DIM}" "${META_COMPOSITE_WARP}" "${SUBJ2META_LOGJD}" 1 "${JAC_GEOM}"

  printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
    "${subject_id}" \
    "${age}" \
    "${t1_brain}" \
    "${BIN_LABEL}" \
    "${BIN_TEMPLATE}" \
    "${REG_PREFIX}1Warp.nii.gz" \
    "${REG_PREFIX}1InverseWarp.nii.gz" \
    "${REG_PREFIX}0GenericAffine.mat" \
    "${SUBJ_IN_BIN}" \
    "${SUBJ2BIN_JD}" \
    "${SUBJ2BIN_LOGJD}" \
    "${BIN2META_WARP}" \
    "${BIN2META_AFFINE}" \
    "${META_COMPOSITE_WARP}" \
    "${SUBJ_IN_META}" \
    "${SUBJ2META_JD}" \
    "${SUBJ2META_LOGJD}" \
    >> "${MANIFEST}"
done < "${SUBJ_TABLE}"

echo "Wrote: ${MANIFEST}"
