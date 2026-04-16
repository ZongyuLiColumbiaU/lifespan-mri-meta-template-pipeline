#!/usr/bin/env bash
set -euo pipefail

# Apply subject-space derived maps (AI-CBV or any other scalar/label image already
# aligned to the subject T1) to both:
#   1) nearest age-bin template space
#   2) meta-template space
#
# Usage:
#   bash 06_apply_additional_maps_example.sh config.sh subject_maps.csv
#
# CSV columns:
#   subject_id,map_path[,map_name[,interp]]
#
# Example:
#   subject_id,map_path,map_name,interp
#   sub-0001,/data/aicbv/sub-0001_AICBV.nii.gz,AICBV,Linear
#   sub-0001,/data/seg/sub-0001_aseg.nii.gz,aseg,GenericLabel
#   sub-0002,/data/cbv/sub-0002_map.nii.gz,,Linear

source "${1:-./config.sh}"
MAP_CSV="${2:-}"

if [[ -z "${MAP_CSV}" ]]; then
  echo "Usage: $0 <config.sh> <subject_maps.csv>" >&2
  exit 1
fi

META_TEMPLATE="${OUTDIR}/meta/meta_template_space.nii.gz"
MANIFEST="${OUTDIR}/subjects_to_meta/manifest.csv"
LOG_DIR="${OUTDIR}/logs"
mkdir -p "${LOG_DIR}"

if [[ ! -f "${META_TEMPLATE}" ]]; then
  echo "Meta-template not found: ${META_TEMPLATE}" >&2
  exit 1
fi

if [[ ! -f "${MANIFEST}" ]]; then
  echo "Subject manifest not found: ${MANIFEST}. Run step 5 first." >&2
  exit 1
fi

if [[ ! -f "${MAP_CSV}" ]]; then
  echo "Map CSV not found: ${MAP_CSV}" >&2
  exit 1
fi

if ! command -v "${ANTS_APPLY}" >/dev/null 2>&1; then
  echo "antsApplyTransforms not found: ${ANTS_APPLY}" >&2
  exit 1
fi

lookup_subject_row() {
  local sid="$1"
  awk -F, -v s="$sid" 'NR>1 && $1==s {print $0; exit}' "${MANIFEST}"
}

sanitize_name() {
  local raw="$1"
  raw="${raw##*/}"
  raw="${raw%.nii.gz}"
  raw="${raw%.nii}"
  raw="${raw// /_}"
  raw="${raw//[^A-Za-z0-9._-]/_}"
  echo "$raw"
}

tail -n +2 "${MAP_CSV}" | while IFS=, read -r subject_id map_path map_name interp; do
  [[ -z "${subject_id}" || -z "${map_path}" ]] && continue

  if [[ ! -f "${map_path}" ]]; then
    echo "[SKIP] ${subject_id}: missing map ${map_path}" >&2
    continue
  fi

  row=$(lookup_subject_row "${subject_id}")
  if [[ -z "${row}" ]]; then
    echo "[SKIP] ${subject_id}: not found in ${MANIFEST}" >&2
    continue
  fi

  IFS=, read -r sid age t1_brain bin_label bin_template subj_warp subj_invwarp subj_affine subj_in_bin subj_jd subj_logjd bin_warp bin_affine meta_composite subj_in_meta meta_jd meta_logjd <<< "${row}"

  if [[ -z "${map_name}" ]]; then
    map_name=$(sanitize_name "$(basename "${map_path}")")
  else
    map_name=$(sanitize_name "${map_name}")
  fi

  if [[ -z "${interp}" ]]; then
    interp="Linear"
  fi

  SUBJ_DIR="${OUTDIR}/subjects_to_meta/${subject_id}"
  BIN_MAP_DIR="${SUBJ_DIR}/maps_in_bin"
  META_MAP_DIR="${SUBJ_DIR}/maps_in_meta"
  mkdir -p "${BIN_MAP_DIR}" "${META_MAP_DIR}"

  OUT_BIN="${BIN_MAP_DIR}/${map_name}_in_${bin_label}.nii.gz"
  OUT_META="${META_MAP_DIR}/${map_name}_in_meta.nii.gz"

  # Subject -> nearest age-bin template
  "${ANTS_APPLY}" -d "${DIM}" \
    -i "${map_path}" \
    -r "${bin_template}" \
    -o "${OUT_BIN}" \
    -n "${interp}" \
    -t "${subj_warp}" \
    -t "${subj_affine}" \
    > "${LOG_DIR}/${subject_id}_${map_name}_to_bin.log" 2>&1

  # Subject -> meta template (uses the composite displacement field from step 5)
  "${ANTS_APPLY}" -d "${DIM}" \
    -i "${map_path}" \
    -r "${META_TEMPLATE}" \
    -o "${OUT_META}" \
    -n "${interp}" \
    -t "${meta_composite}" \
    > "${LOG_DIR}/${subject_id}_${map_name}_to_meta.log" 2>&1

  echo "Wrote: ${OUT_BIN}"
  echo "Wrote: ${OUT_META}"
done
