#!/usr/bin/env Rscript
# Usage: Rscript --vanilla scripts/run_bulk.R SPEC.json PROFILE.json
# Relative data/output paths in a profile are resolved against the runner root.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("Usage: Rscript --vanilla scripts/run_bulk.R SPEC.json PROFILE.json", call. = FALSE)
spec_file <- normalizePath(args[1L], mustWork = TRUE)
profile_file <- normalizePath(args[2L], mustWork = TRUE)
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
root <- dirname(dirname(normalizePath(script, mustWork = TRUE)))
Sys.setenv(TRANSCRIPTOMICS_ROOT = root)
setwd(root)
source("environment/runtime.R")
source("scripts/bulk_run.R")
dir <- run_bulk(bulk_read_json(spec_file), bulk_read_json(profile_file), progress = message, entry_point = "cli")
cat(jsonlite::toJSON(list(status = "complete", directory = dir, report = file.path(dir, "report.html")),
                     auto_unbox = TRUE), "\n")
