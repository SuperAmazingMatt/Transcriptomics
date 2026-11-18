# Shared count-run contract. Load environment/runtime.R before sourcing this file.
source(file.path(project_root, "scripts", "bulk_analysis.R"), local = TRUE)
source(file.path(project_root, "scripts", "report", "render_report.R"), local = TRUE)

bulk_json <- function(value, path) {
  jsonlite::write_json(value, path, auto_unbox = TRUE, pretty = TRUE,
                       digits = NA, null = "null", na = "null")
}
bulk_read_json <- function(path) jsonlite::read_json(path, simplifyVector = FALSE)
bulk_hash <- function(path) unname(as.character(tools::sha256sum(path)))
bulk_utc <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")

bulk_text <- function(x, label) {
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(trimws(x))) {
    stop(label, " must be a nonempty string.")
  }
  x
}

bulk_fields <- function(x, allowed, required, label) {
  if (!is.list(x) || (length(x) && is.null(names(x))) || anyDuplicated(names(x)) ||
      length(setdiff(names(x), allowed)) || length(setdiff(required, names(x)))) {
    stop("Invalid fields in ", label, ". Required: ", paste(required, collapse = ", "),
         ". Supported: ", paste(allowed, collapse = ", "), ".")
  }
}

bulk_path <- function(path) {
  path <- path.expand(bulk_text(path, "Path"))
  if (!grepl("^(/|[A-Za-z]:[/\\\\]|\\\\\\\\)", path)) path <- file.path(project_root, path)
  path
}

bulk_config <- function(spec, profile) {
  bulk_fields(spec, c("schema_version","preset","dataset","inputs","settings"), 
              c("schema_version","preset","dataset","inputs"), "run specification")
  bulk_fields(profile, c("schema_version","paths","output_root"),
              c("schema_version","paths","output_root"), "execution profile")
  for (version in list(spec$schema_version, profile$schema_version)) {
    if (!is.numeric(version) || !isTRUE(version == 1L) || length(version) != 1L) {
      stop("Expected schema_version 1.")
    }
  }
  if (!identical(spec$preset, "bulk-expression-v1")) stop("Unknown expression preset.")
  bulk_fields(spec$dataset, c("id","species","assembly","annotation","notes"), "id", "dataset")
  invisible(Map(bulk_text, spec$dataset, names(spec$dataset)))
  bulk_fields(spec$inputs, c("counts","samples","summary"), "counts", "inputs")
  ids <- vapply(spec$inputs, bulk_text, character(1), label = "Input identifier")
  if (anyDuplicated(ids)) stop("Each input needs its own logical identifier.")
  if (!is.list(profile$paths) || anyDuplicated(names(profile$paths)) ||
      !all(ids %in% names(profile$paths))) stop("Missing or ambiguous input path in profile.")
  paths <- lapply(ids, function(id) {
    path <- normalizePath(bulk_path(profile$paths[[id]]), winslash = "/", mustWork = TRUE)
    if (dir.exists(path)) stop("Expected a file at ", path)
    path
  })
  dest <- bulk_path(profile$output_root)
  # Resolve existing ancestors before creating new directories, including .. and symlinks.
  resolve_dir <- function(path) {
    if (dir.exists(path)) return(normalizePath(path, winslash = "/", mustWork = TRUE))
    if (basename(path) %in% c(".", "..", "") || identical(path, dirname(path))) {
      stop("Invalid output directory.")
    }
    file.path(resolve_dir(dirname(path)), basename(path))
  }
  dest <- resolve_dir(dest)
  roots <- file.path(project_root, c("data","references","environment","scripts","app","config","records",".git"))
  if (.Platform$OS.type == "windows") {
    roots <- tolower(roots)
    compared <- tolower(dest)
  } else compared <- dest
  if (any(compared == roots | startsWith(compared, paste0(roots, "/")))) {
    stop("Choose results/ or a separate output location outside project sources and archives.")
  }
  list(paths = paths, output_root = dest)
}

bulk_versions <- function() {
  quarto <- Sys.which("quarto")
  if (!nzchar(quarto)) stop("Quarto CLI is required. Activate the environment before running.")
  quarto_version <- system2(quarto, "--version", stdout = TRUE, stderr = TRUE)
  if (!length(quarto_version) || !is.null(attr(quarto_version, "status"))) stop("Quarto version check failed.")
  packages <- c("edgeR","limma","data.table","ggplot2","ggrepel","ragg","jsonlite",
                "shiny","knitr","rmarkdown","processx","htmltools","BiocVersion")
  versions <- lapply(stats::setNames(packages, packages), function(pkg) {
    loadNamespace(pkg)
    as.character(getNamespaceVersion(pkg))
  })
  c(list(R = as.character(getRversion()), platform = R.version$platform,
         quarto = paste(quarto_version, collapse = " ")), versions)
}

run_bulk <- function(spec, profile, progress = function(stage) NULL, entry_point = "R") {
  if (!is.character(entry_point) || length(entry_point) != 1L ||
      !entry_point %in% c("R","shiny","cli")) stop("Unknown analysis entry point.")
  config <- bulk_config(spec, profile)
  dest <- config$output_root
  if (!dir.exists(dest) && !dir.create(dest, recursive = TRUE) && !dir.exists(dest)) stop("Cannot create output root.")
  work <- tempfile("pending-", tmpdir = dest)
  if (!dir.create(work)) stop("Cannot reserve run directory.")
  id <- paste0(format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC"), "-", sub("^pending-", "", basename(work)))
  final <- file.path(dest, paste0("bulk-", id))
  log_path <- file.path(work, "run.log")
  start <- proc.time()[["elapsed"]]
  stage <- "setup"
  mark <- function(name) {
    stage <<- name
    cat(bulk_utc(), name, "\n", file = log_path, append = TRUE)
    progress(name)
  }
  tryCatch({
    index <- list(schema_version = 1L, run_id = id, started_utc = bulk_utc(),
                  status = "running", entry_point = entry_point, dataset = spec$dataset, preset = spec$preset)
    mark("Validate inputs")
    bulk_json(spec, file.path(work, "submitted.json"))
    bulk_json(profile, file.path(work, "profile.json"))
    index$versions <- bulk_versions()
    index$inputs <- Map(function(path, logical_id) {
      list(logical_id = logical_id, path = path, sha256 = bulk_hash(path))
    }, config$paths, spec$inputs[names(config$paths)])
    imported <- do.call(bulk_import, config$paths)
    index$settings <- bulk_settings(if (is.null(spec$settings)) list() else spec$settings, imported)
    index$timings_seconds <- list(intake = proc.time()[["elapsed"]] - start)
    mark("Compute expression and sample QC")
    before_analysis <- proc.time()[["elapsed"]]
    analysis <- bulk_analyze(imported, index$settings, work)
    index$timings_seconds$analysis_and_exports <- proc.time()[["elapsed"]] - before_analysis
    index$outputs <- analysis$files
    analysis$files <- NULL
    index$summary <- analysis
    index$stages <- list(intake = "Complete", expression = "Complete", sample_qc = "Complete",
                         comparison = "Skipped (descriptive analysis requested)",
                         pathways = "Skipped (no comparison requested)",
                         read_qc = "Skipped (input begins at gene counts)")
    sources <- c("scripts/bulk_analysis.R","scripts/bulk_run.R","scripts/report/render_report.R",
                 "scripts/report/report.qmd","environment/runtime.R","environment/renv.lock")
    if (entry_point == "cli") sources <- c(sources, "scripts/run_bulk.R")
    if (entry_point == "shiny") sources <- c(sources, "app/app.R", "app/explorer_server.R", "app/interface.R", "app/explorer.css")
    index$source_sha256 <- as.list(setNames(bulk_hash(file.path(project_root, sources)), sources))
    # Store the experiment choices, host-specific paths, and source identities side by side.
    bulk_json(index[c("schema_version","entry_point","preset","dataset","settings","inputs","versions","source_sha256")],
              file.path(work, "resolved.json"))
    writeLines(capture.output(utils::sessionInfo()), file.path(work, "session.txt"))
    index$outputs <- c(index$outputs, list(submitted = "submitted.json", profile = "profile.json",
                        resolved = "resolved.json", session = "session.txt", log = "run.log"))
    mark("Render Quarto report")
    before_report <- proc.time()[["elapsed"]]
    index$outputs$report <- render_bulk_report(work, index)
    index$timings_seconds$report <- proc.time()[["elapsed"]] - before_report
    index$stages$report <- "Complete"
    mark("Verify and save")
    for (input in index$inputs) {
      if (!identical(bulk_hash(input$path), input$sha256)) stop("Input changed during analysis: ", input$logical_id)
    }
    index$status <- "complete"
    index$finished_utc <- bulk_utc()
    index$output_sha256 <- lapply(index$outputs, function(path) bulk_hash(file.path(work, path)))
    if (.Platform$OS.type == "windows") {
      index$R_process_peak_working_set_bytes <- unname(ps::ps_memory_info()["peak_wset"])
    }
    index$timings_seconds$total <- proc.time()[["elapsed"]] - start
    bulk_json(index, file.path(work, "index.json"))
    if (dir.exists(final) || !file.rename(work, final)) stop("Could not publish completed run.")
    normalizePath(final, winslash = "/", mustWork = TRUE)
  }, error = function(e) {
    # A failed work directory is diagnostic only and cannot be opened as a completed run.
    if (dir.exists(work)) {
      if (file.exists(file.path(work, "index.json"))) file.remove(file.path(work, "index.json"))
      cat(bulk_utc(), conditionMessage(e), "\n", file = log_path, append = TRUE)
      bulk_json(list(status = "failed", stage = stage, message = conditionMessage(e)),
                file.path(work, "failure.json"))
    }
    stop(conditionMessage(e), "\nRun diagnostics: ", work, call. = FALSE)
  })
}

open_bulk_run <- function(dir) {
  dir <- normalizePath(bulk_text(dir, "Run directory"), winslash = "/", mustWork = TRUE)
  index <- bulk_read_json(file.path(dir, "index.json"))
  required <- c("raw","cpm","logcpm","display","qc","mapping","report","resolved","log")
  if (!identical(index$schema_version, 1L) || !identical(index$status, "complete") ||
      !all(required %in% names(index$outputs)) || anyDuplicated(names(index$outputs)) ||
      !identical(names(index$outputs), names(index$output_sha256))) stop("Invalid or incomplete run index.")
  for (key in names(index$outputs)) {
    rel <- bulk_text(index$outputs[[key]], "Indexed output")
    if (!grepl("^[A-Za-z0-9_./-]+$", rel) || startsWith(rel, "/") ||
        any(strsplit(rel, "/", fixed = TRUE)[[1L]] %in% c("",".",".."))) stop("Invalid relative output path.")
    path <- normalizePath(file.path(dir, rel), winslash = "/", mustWork = TRUE)
    if (!startsWith(path, paste0(dir, "/")) || dir.exists(path) ||
        !identical(bulk_hash(path), index$output_sha256[[key]])) stop("Output verification failed: ", key)
  }
  list(dir = dir, index = index)
}
