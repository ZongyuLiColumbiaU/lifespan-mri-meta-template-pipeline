# Lifespan MRI Meta-Template Pipeline

ANTs-based pipeline for building age-bin templates, constructing a second-stage unbiased meta-template, registering subjects into meta-template space, propagating subject-space scalar maps, and generating Jacobian determinant maps for tensor-based morphometry (TBM).

## Overview

This repository implements a hierarchical template strategy for lifespan T1-weighted MRI studies with approximately 3,000 preprocessed scans spanning ages 10 to 100 years in 10-year bins.

Workflow:

1. Build age-bin unbiased templates.
2. Affinely align bin templates to remove gross pose and scale differences.
3. Build a second-stage unbiased template from the aligned bin templates.
4. Use the second-stage template as the meta-template space.
5. Register each subject to its nearest age-bin template and compose transforms into meta-space.
6. Propagate subject-space scalar maps such as AI-CBV into age-bin and meta-template space, and generate Jacobian determinant maps for TBM.

The pipeline is designed for cohorts whose structural MRI has already undergone upstream preprocessing such as FreeSurfer-based affine normalization and brain extraction.

## Key features

- Age-specific unbiased template construction in 10-year bins from 10 to 100 years.
- Second-stage unbiased meta-template construction.
- Subject-to-bin and subject-to-meta registration.
- Forward propagation of scalar maps from subject space to bin and meta space.
- Jacobian determinant and log-Jacobian outputs for TBM in bin and meta space.
- Modular shell and Python scripts suitable for local execution or adaptation to SLURM.

## Repository contents

- `00_make_bins_and_lists.py`  
  Create age-bin manifests and per-bin subject lists from the cohort CSV.

- `01_build_age_bin_templates.sh`  
  Build unbiased T1 templates for each age bin using ANTs.

- `02_affine_align_bin_templates.sh`  
  Affinely align age-bin templates to a mid-life anchor to remove gross pose and scale differences before second-stage construction.

- `03_build_meta_template.sh`  
  Build the second-stage unbiased meta-template from the affinely aligned age-bin templates.

- `04_register_bins_to_meta.sh`  
  Register each age-bin template to the final meta-template.

- `05_register_subjects_to_bin_and_compose.sh`  
  Register every subject to the nearest age-bin template, compose subject-to-meta transforms, warp subject T1 to meta space, and generate Jacobian determinant maps for TBM.

- `06_apply_additional_maps_example.sh`  
  Apply subject-space scalar maps such as AI-CBV to the nearest age-bin template space and to the meta-template space using the transforms from step 5.

- `config.example.sh`  
  Example configuration file.

## Requirements

- ANTs installed and available on `PATH`
- Bash
- Python 3
- Brain-extracted T1w MRI in a common approximate affine space

Recommended:

- ANTs 2.6.0 or newer for robust composite transform workflows
- Sufficient CPU cores and memory for template building

## Input format

Main cohort CSV:

```csv
subject_id,age,t1_brain
sub-0001,12.4,/data/t1_brains/sub-0001_T1w_brain.nii.gz
sub-0002,19.8,/data/t1_brains/sub-0002_T1w_brain.nii.gz
sub-0003,67.2,/data/t1_brains/sub-0003_T1w_brain.nii.gz
```

Optional scalar-map CSV for step 6:

```csv
subject_id,age,map_path,map_name,map_type
sub-0001,12.4,/data/maps/sub-0001_AICBV.nii.gz,AICBV,scalar
sub-0001,12.4,/data/maps/sub-0001_probGM.nii.gz,probGM,scalar
sub-0001,12.4,/data/maps/sub-0001_seg.nii.gz,segmentation,label
```

## Recommended execution order

### 1. Copy and edit the configuration

```bash
cp config.example.sh config.sh
```

### 2. Build age-bin templates

```bash
bash 01_build_age_bin_templates.sh config.sh
```

### 3. Affinely align bin templates

```bash
bash 02_affine_align_bin_templates.sh config.sh
```

### 4. Build the second-stage meta-template

```bash
bash 03_build_meta_template.sh config.sh
```

### 5. Register bin templates to meta-template space

```bash
bash 04_register_bins_to_meta.sh config.sh
```

### 6. Register subjects to nearest-age bins and compose into meta-template space

```bash
bash 05_register_subjects_to_bin_and_compose.sh config.sh
```

### 7. Propagate AI-CBV and other maps to bin and meta space

```bash
bash 06_apply_additional_maps_example.sh config.sh subject_maps.csv
```

## Directory structure

A typical output tree looks like this:

```text
OUTDIR/
  age_bins/
    10_20/
      subjects.txt
      subjects.csv
      template_build/
    20_30/
      ...
  meta/
    bin_templates_affine/
    meta_template_build/
    meta_template_space.nii.gz
    bin_to_meta/
  subject_to_bin/
    10-20/
      sub-0001_to_10-20_0GenericAffine.mat
      sub-0001_to_10-20_1Warp.nii.gz
  subjects_to_meta/
    sub-0001/
      sub-0001_T1_in_meta.nii.gz
      sub-0001_JD_in_meta.nii.gz
      sub-0001_logJD_in_meta.nii.gz
  mapped_subject_maps/
    AICBV/
      meta/
      age_bins/
  logs/
```

## Jacobian determinant outputs for TBM

Step 5 writes Jacobian determinant products in both bin space and meta space.

Typical outputs include:

- Subject-to-bin Jacobian determinant map
- Subject-to-bin log-Jacobian map
- Subject-to-meta Jacobian determinant map
- Subject-to-meta log-Jacobian map

These can be used for TBM analyses after QC and masking.

## Notes on interpolation

- Use `Linear` or `BSpline` for continuous scalar maps such as AI-CBV.
- Use `GenericLabel` for label images and segmentations.
- Do not use nearest-neighbor interpolation for quantitative scalar maps.

## Practical recommendations

### Template sample size per bin

With approximately 3,000 scans across nine bins, the average may be around 300 scans per bin, but the distribution is rarely uniform. A practical approach is:

- First-pass template build: 100 to 200 scans per bin, balanced when possible
- Final registration: all subjects

### Why affine alignment is separate from the final meta-template

The affine alignment in step 2 is only used to remove large pose and scale differences between age-bin templates before second-stage unbiased construction. The final meta-template is still the second-stage unbiased template from step 3.

### QC that should not be skipped

Inspect at least:

- Each age-bin template
- Each affinely aligned bin template
- The final meta-template
- A random sample of subject T1 scans in meta space
- A random sample of propagated AI-CBV or other maps in meta space
- Jacobian maps for implausible folding, spikes, or boundary artifacts

Suggested quantitative QC:

- Brain-mask overlap
- NCC or CC to the target template
- Ventricle sharpness and boundary consistency
- Distribution of log-Jacobians within brain mask

## Important caveats

This is a strong starting framework, not a universal production pipeline. You will likely want to tune:

- Number of template-building iterations
- Per-bin sampling strategy
- Registration regularization
- Thread and job parallelization
- Intensity normalization consistency
- QC and restart handling

## Suggested citation context

This repository follows the standard logic of unbiased ANTs template construction and transform composition for forward image mapping. It is intended for lifespan neuroimaging studies where a single young-adult reference space is suboptimal for aging analyses.

## License

This project is released under the MIT License. See `LICENSE`.
