# Render outside the run so Quarto scratch files and source never enter the output index.
render_bulk_report <- function(dir, index) {
  run_dir <- normalizePath(dir, winslash = "/", mustWork = TRUE)
  template <- file.path(project_root, "scripts", "report", "report.qmd")
  quarto <- Sys.which("quarto")
  if (!nzchar(quarto)) stop("Quarto is required to render report.html. Activate the project environment.")
  scratch <- tempfile("transcriptomics-report-")
  if (!dir.create(scratch)) stop("Cannot create the report rendering directory.")
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
  if (!file.copy(template, file.path(scratch, "report.qmd"))) stop("Cannot copy the Quarto template.")
  saveRDS(list(dir = run_dir, index = index), file.path(scratch, "report-input.rds"))

  result <- processx::run(quarto, c("render", "report.qmd", "--to", "html"),
                          wd = scratch, error_on_status = FALSE)
  rendered <- file.path(scratch, "report.html")
  if (result$status != 0L || !file.exists(rendered)) {
    stop("Quarto render failed.\n", result$stdout, "\n", result$stderr)
  }
  if (!file.copy(rendered, file.path(run_dir, "report.html"))) {
    stop("Cannot publish the rendered report in the run directory.")
  }
  "report.html"
}
