# Run a bulk expression analysis

Unpack the runner on the compute host. Provide the R version in `environment/renv.lock`, Quarto CLI on PATH, and the system libraries/build tools needed by those packages. From the extracted `count-runner` directory, restore the private R library with `Rscript --vanilla environment/setup.R`. Set the host locale to UTF-8. The local development checks ran on Windows. A Linux/STRUDEL installation needs its own restore and acceptance run.

Save this experiment specification as `run.json`. Replace the dataset description with the actual organism and reference information. Values can be marked unknown. The gene count file must be a tab-separated featureCounts table with its six standard annotation columns and raw nonnegative integer counts.

```json
{
  "schema_version": 1,
  "preset": "bulk-expression-v1",
  "dataset": {"id": "my-libraries", "species": "unknown", "assembly": "unknown", "annotation": "unknown"},
  "inputs": {"counts": "counts", "samples": "samples", "summary": "summary"},
  "settings": {"detection_cpm": 1, "min_samples": 1, "display_scale": "logCPM", "pca_genes": 500, "color_by": "none"}
}
```

Save the host paths as `profile.json`. Relative paths start at the runner root. The sample sheet is a CSV with a unique `sample_id` and the exact original header in `count_column` for each library. Additional columns supply sample annotations. The optional featureCounts summary checks each library's Assigned total against its count-column sum. Supply this summary for single-assignment counts where these quantities should agree. Omit the corresponding entries from `inputs` for either optional file when unavailable. Without a sheet the count headers identify the libraries.

```json
{
  "schema_version": 1,
  "paths": {"counts": "/data/counts.txt", "samples": "/data/samples.csv", "summary": "/data/counts.txt.summary"},
  "output_root": "/work/expression-results"
}
```

Run `Rscript --vanilla scripts/run_bulk.R run.json profile.json`. Progress goes to stderr. On success, stdout gives the new directory and HTML report as JSON. Each invocation creates a fresh run. Failures return a nonzero exit and, if execution began, a diagnostic directory. Correct the cause and run again.

Copy the entire completed directory back to the workstation. Open its `report.html` directly or enter the directory in the app's saved-run control. Keep the subdirectories, index and filenames together. The app verifies every indexed file's SHA-256 digest before displaying results. The resolved configuration and profile include original input paths, which may identify the source host.

The display threshold uses TMM CPM, inclusively, across the selected minimum number of libraries. A value of three requires detection in at least three libraries. The display scale accepts `CPM` and `logCPM`. All-gene raw counts, CPM, log-CPM and sample QC are exported alongside the filtered table. Group color takes a sample-sheet column name or `none`. QC and PCA use their own recorded gene sets. A single library has a normalization factor of one. The analysis is descriptive and requires no group or comparison.

Build a fresh distribution from the full project with `python scripts/package_runner.py results/count-runner.zip`, using a new destination filename for each build.
