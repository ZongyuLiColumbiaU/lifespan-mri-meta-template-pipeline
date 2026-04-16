#!/usr/bin/env bash
set -euo pipefail
source "${1:-./config.sh}"
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS="${OMP_THREADS}"

mkdir -p "${OUTDIR}/logs"
python3 00_make_bins_and_lists.py \
  --csv "${STUDY_CSV}" \
  --outdir "${OUTDIR}" \
  --bin-start "${BIN_START}" \
  --bin-end "${BIN_END}" \
  --bin-size "${BIN_SIZE}" \
  --max-per-bin "${MAX_PER_BIN}" \
  --seed "${RANDOM_SEED}"

while IFS=, read -r bin n age_min age_max age_mean; do
  [[ "${bin}" == "bin" ]] && continue
  if [[ "${n}" -lt 2 ]]; then
    echo "[SKIP] ${bin}: not enough subjects (${n})"
    continue
  fi
  BIN_DIR="${OUTDIR}/age_bins/${bin}"
  LIST_FILE="${BIN_DIR}/subjects.txt"
  WORK_DIR="${BIN_DIR}/template_build"
  mkdir -p "${WORK_DIR}"

  mapfile -t IMGS < "${LIST_FILE}"
  if [[ -n "${TARGET_SPACING}" ]]; then
    PREP_DIR="${BIN_DIR}/resampled"
    mkdir -p "${PREP_DIR}"
    RESAMPLED=()
    for img in "${IMGS[@]}"; do
      base=$(basename "${img}")
      out="${PREP_DIR}/${base%.nii.gz}_iso.nii.gz"
      if [[ ! -f "${out}" ]]; then
        ${RESAMPLE} ${DIM} "${img}" "${out}" ${TARGET_SPACING//x/ } 0 4
      fi
      RESAMPLED+=("${out}")
    done
    IMGS=("${RESAMPLED[@]}")
  fi

  pushd "${WORK_DIR}" >/dev/null
  # Notes:
  # - antsMultivariateTemplateConstruction2.sh is the newer ANTs template script.
  # - -c 2 uses local parallel execution, -j sets number of jobs.
  # - We disable N4 here by default because upstream preprocessing often already handled it.
  ${ANTS_MULTIVAR_TEMPLATE} \
    -d ${DIM} \
    -o "${bin}_" \
    -i "${TEMPLATE_ITER}" \
    -g "${TEMPLATE_GRADIENT_STEP}" \
    -j "${TEMPLATE_BUILD_JOBS}" \
    -k 1 \
    -w 1 \
    -c "${TEMPLATE_BUILD_PARALLEL_MODE}" \
    -n "${TEMPLATE_DO_N4}" \
    -r 1 \
    -m "${TEMPLATE_MAX_ITERS}" \
    -f "${TEMPLATE_SHRINK_FACTORS}" \
    -s "${TEMPLATE_SMOOTHING_SIGMAS}" \
    -t "${TEMPLATE_TRANSFORM}" \
    "${IMGS[@]}" \
    2>&1 | tee "${OUTDIR}/logs/${bin}_template_build.log"
  popd >/dev/null

done < "${OUTDIR}/meta/bin_summary.csv"
