#!/usr/bin/env bash
# Copy to config.sh and edit.

# ---------- Required ----------
export STUDY_CSV="/path/to/study_cohort.csv"
# CSV columns required: subject_id,age,t1_brain
# t1_brain should be a brain-extracted T1w NIfTI already roughly aligned
# (e.g., after FreeSurfer/affine preprocessing).

export OUTDIR="/path/to/lifespan_template_work"
export DIM=3
export BIN_START=10
export BIN_END=100
export BIN_SIZE=10

# ---------- ANTs executables ----------
# Put full paths here if they are not already on PATH.
export ANTS_MULTIVAR_TEMPLATE="antsMultivariateTemplateConstruction2.sh"
export ANTS_REG="antsRegistration"
export ANTS_APPLY="antsApplyTransforms"
export RESAMPLE="ResampleImageBySpacing"
export IMAGE_MATH="ImageMath"

# ---------- Compute ----------
# antsMultivariateTemplateConstruction2.sh parallel mode:
#   0 serial, 1 SGE, 2 local PEXEC, 4 PBS, 5 SLURM
export TEMPLATE_BUILD_PARALLEL_MODE=2
export TEMPLATE_BUILD_JOBS=24
export OMP_THREADS=4

# ---------- Sampling ----------
# For ~3k scans, you may not want every scan in each template build.
# 0 means use all scans in the bin.
export MAX_PER_BIN=0
export RANDOM_SEED=42

# ---------- Template building parameters ----------
# Conservative defaults for adult/aging T1w brains already roughly aligned.
export TEMPLATE_ITER=4
export TEMPLATE_TRANSFORM="SyN"
export TEMPLATE_METRIC="CC"
export TEMPLATE_GRADIENT_STEP=0.15
export TEMPLATE_MAX_ITERS="100x70x50x10"
export TEMPLATE_SHRINK_FACTORS="8x4x2x1"
export TEMPLATE_SMOOTHING_SIGMAS="3x2x1x0vox"
# N4 is usually unnecessary if your preprocessing already handled bias; set 1 if desired.
export TEMPLATE_DO_N4=0

# ---------- Pairwise template-to-template affine alignment ----------
export AFFINE_METRIC="MI"
export AFFINE_ITERS="1000x500x250x100"
export AFFINE_SHRINK="8x4x2x1"
export AFFINE_SMOOTH="3x2x1x0vox"

# ---------- Subject -> age-template nonlinear registration ----------
export SUBJ_TO_BIN_METRIC_LINEAR="MI"
export SUBJ_TO_BIN_METRIC_SYN="CC"
export SUBJ_TO_BIN_ITERS_LINEAR="1000x500x250x100"
export SUBJ_TO_BIN_ITERS_SYN="100x70x50x20"
export SUBJ_TO_BIN_SHRINK="8x4x2x1"
export SUBJ_TO_BIN_SMOOTH="3x2x1x0vox"
export SUBJ_TO_BIN_SYN="SyN[0.10,3,0]"


# ---------- Jacobian maps / TBM ----------
# ANTs >= 2.6.0 recommended for direct composite transform output from antsApplyTransforms
# ANTs >= 2.6.1 recommended for Jacobian estimation with non-identity direction matrices.
export CREATE_JACOBIAN="CreateJacobianDeterminantImage"
# 1 = geometric Jacobian (recommended for TBM), 0 = analytic Jacobian
export JACOBIAN_USE_GEOMETRIC=1

# ---------- Optional isotropic spacing normalization ----------
# Leave blank to skip. Example: 1x1x1 or 0.8x0.8x0.8
export TARGET_SPACING=""
