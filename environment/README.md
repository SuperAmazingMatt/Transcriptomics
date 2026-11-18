# Count-mode development environment

The local Windows setup uses R 4.6.1, Bioconductor 3.23 and the private `environment/R-library/`. The [renv lock](renv.lock) pins 132 packages, including Shiny 1.14.0, edgeR 4.10.7 and limma 3.68.5. R supplies its base and recommended libraries. Quarto CLI 1.9.38 is provided separately by the local RStudio installation.

## Open and check

From the project root in PowerShell:

```powershell
. ./environment/Activate.ps1
Rscript --vanilla scripts/00_check_environment.R
```

Activation selects the project R library for this shell and its children, including Quarto. It discovers the matching Windows R installation and standalone or RStudio-bundled Quarto. Set `TRANSCRIPTOMICS_RSCRIPT` if Rscript lives elsewhere. Opening `Transcriptomics.Rproj` in RStudio also loads the project runtime. Add `--write-receipt` to the check to refresh the local inventory and session information under `records/`.

To exercise the HTML reporting engine after activation, copy [check_report.qmd](check_report.qmd) to an empty temporary folder and run `quarto render check_report.qmd` in that folder. The document checks the child R session's package paths, loads the reporting and analysis packages, and evaluates a Shiny reactive value. The rendered page should contain **Runtime check passed with value 42.** It uses no project data.

## Restore and extend

Run `./environment/Setup.ps1` to restore the locked packages to the project library on Windows. The underlying entry point is `Rscript --vanilla environment/setup.R` from the project root. For a clean host, provide the locked R version, access to the package sources and any build tools/system libraries they require. For HTML rendering, provide a compatible Quarto installation and verify the render above. On Linux, restore packages built for that platform.

Keep the shared runtime focused on the current bulk count module. Add dependencies for FASTQ, single-cell or spatial processing when their modules are implemented. When a dependency changes, update the lock, verify its versions and origins in a fresh R session, rerun the report check and record the change. Keep machine-specific libraries, large reads, genome indexes and workflow scratch out of a runner distribution. Use compute storage outside OneDrive for future FASTQ work.

## Verification on 18 November 2026

The local library was populated with compatible installed Windows packages. The project check matched all 132 locked package versions, loaded all 16 named entry packages, and checked the origins of loaded namespaces. Repeating setup on the populated library succeeded. An independent Quarto render in a temporary directory produced the expected HTML with the isolated R library. The full research workspace records data-integrity checks separately in its local work log.

The local Shiny and headless BMS runs produced numerically equivalent expression and QC outputs with this environment. The local acceptance receipt records the actual versions and timings. A fresh restore from package repositories, Linux/STRUDEL setup, `tximport`, nf-core execution and sequencing references require separate verification.
