# Run from the project root in a fresh R session. Only --write-receipt writes files.
source("environment/runtime.R", local = TRUE)
if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("Install the project library with environment/setup.R before checking it.")
}
lock <- jsonlite::read_json("environment/renv.lock", simplifyVector = FALSE)
package_groups <- list(
  count_analysis = c("jsonlite", "edgeR", "limma"),
  mouse_reference = c("AnnotationDbi", "org.Mm.eg.db", "GO.db"),
  historical_script_dependencies = c("tidyverse", "ggplot2", "ggrepel", "ggfortify"),
  interface_and_reporting = c("shiny", "knitr", "rmarkdown"),
  setup = c("renv", "BiocManager", "BiocVersion")
)
entry_packages <- unique(unlist(package_groups, use.names = FALSE))
loadable <- vapply(entry_packages, requireNamespace, logical(1), quietly = TRUE)
expected <- vapply(lock$Packages, function(p) p$Version, character(1))
actual <- project_package_versions(names(expected))
different <- names(expected)[is.na(actual) | actual != expected]
library_paths <- normalizePath(.libPaths(), winslash = "/")
private <- normalizePath(project_library, winslash = "/", mustWork = TRUE)
system_library <- normalizePath(.Library, winslash = "/")
path_ok <- identical(library_paths, c(private, system_library))
origins <- vapply(setdiff(loadedNamespaces(), "base"), function(pkg) {
  normalizePath(getNamespaceInfo(pkg, "path"), winslash = "/", mustWork = TRUE)
}, character(1))
allowed_system <- rownames(installed.packages(lib.loc = .Library, priority = c("base", "recommended")))
wrong_origin <- names(origins)[!(dirname(origins) == private |
                                  (dirname(origins) == system_library & names(origins) %in% allowed_system))]
r_ok <- identical(as.character(getRversion()), lock$R$Version)
passed <- r_ok && path_ok && !length(different) && !length(wrong_origin) && all(loadable)
report <- data.frame(package = entry_packages, loadable = unname(loadable),
                     version = unname(actual[entry_packages]), row.names = NULL)
receipt <- list(
  checked_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  scope = "Local R environment and namespace checks; no scientific analysis",
  R = R.version.string, platform = R.version$platform, libraries = library_paths,
  lockfile = "environment/renv.lock", lockfile_sha256 = unname(tools::sha256sum("environment/renv.lock")),
  locked_R = lock$R$Version,
  locked_package_count = length(expected), version_mismatches = unname(as.list(different)),
  namespace_origin_violations = unname(as.list(wrong_origin)), library_paths_isolated = path_ok,
  all_required_loadable = all(loadable), packages = report, passed = passed)
print(report, row.names = FALSE)
cat("R", as.character(getRversion()), "| pinned packages:", length(expected),
    "| isolated local environment check:", if (passed) "PASS\n" else "FAIL\n")
if ("--write-receipt" %in% commandArgs(trailingOnly = TRUE)) {
  if (!dir.exists("records") && !dir.create("records")) stop("Could not create the records directory")
  jsonlite::write_json(receipt, "records/environment_inventory.json",
                       auto_unbox = TRUE, pretty = TRUE, na = "null")
  writeLines(capture.output(sessionInfo()), "records/local_environment_sessionInfo.txt")
}
if (!passed) {
  stop("Environment verification failed. Check R version, private library, package versions and origins. ",
       "Version mismatches: ", paste(different, collapse = ", "),
       ". Wrong origins: ", paste(wrong_origin, collapse = ", "),
       ". Unloadable: ", paste(entry_packages[!loadable], collapse = ", "))
}
