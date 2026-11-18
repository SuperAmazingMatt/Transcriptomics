# Transcriptomics

Explore gene-level featureCounts data in a local Shiny app or run the same analysis from the command line. Both produce complete raw, CPM and log2 CPM tables, sample QC, figures and a standalone Quarto HTML report. Expression exploration works with one or more libraries and requires no comparison.

## Start the explorer

Install R 4.6.1 and Quarto CLI. From the repository root in PowerShell, restore the project library once, then launch the app.

```powershell
./environment/Setup.ps1
./Start-Explorer.ps1
```

Select your featureCounts matrix and optionally supply a sample sheet and assignment summary. Review the sample mapping and gene filter preview, then select **Run expression analysis**. In **Results**, search for genes, inspect QC, download tables or reopen a saved run. The app runs on your computer. Stop it with Ctrl+C.

## Run on a server

The [runner guide](docs/COUNT_RUNNER.md) describes the experiment specification, host-specific file paths and the commands to build and use a portable runner. Return the completed run directory to your workstation to view its report or reopen it in the explorer. The count-mode app and runner were tested on Windows. Verification on the target Linux/HPC host is pending.

## Development and local workspace

The [runtime guide](environment/README.md) covers package isolation and verification. Development checks covered sample-header matching, agreement between the GUI and headless exports, independent display filters, one-library input and reopening a copied run. The next milestone is optional comparisons and pathways. FASTQ processing and additional assays are planned.

In the full research workspace, start a new project chat from `AGENTS.md` and `records/project_state.json`. Design decisions are in `docs/APP_DESIGN.md` and `docs/PIPELINE_PLAN.md`. The work log, validation receipts, example data, sample mappings and analysis outputs are local workspace materials. A source checkout accepts your own inputs.
