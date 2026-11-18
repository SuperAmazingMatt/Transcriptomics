# Load from the project root, or from a child process with its root exported.
project_root <- if (file.exists("environment/runtime.R")) getwd() else Sys.getenv("TRANSCRIPTOMICS_ROOT")
if (!file.exists(file.path(project_root, "environment", "runtime.R"))) {
  stop("Start R from the Transcriptomics project or activate its environment first.")
}
project_root <- normalizePath(project_root, winslash = "/", mustWork = TRUE)
project_library <- file.path(project_root, "environment", "R-library")
if (!dir.exists(project_library) && !dir.create(project_library, showWarnings = FALSE)) {
  stop("Cannot initialize the private project library at ", project_library)
}
.libPaths(c(project_library, .Library), include.site = FALSE)
Sys.setenv(TRANSCRIPTOMICS_ROOT = project_root,
           R_LIBS = project_library, R_LIBS_USER = project_library, R_LIBS_SITE = "NULL",
           R_PROFILE_USER = file.path(project_root, ".Rprofile"))

project_package_versions <- function(packages) {
  vapply(packages, function(pkg) {
    metadata <- file.path(project_library, pkg, "Meta", "package.rds")
    if (!file.exists(metadata)) return(NA_character_)
    record <- tryCatch(readRDS(metadata), error = function(e) NULL)
    if (is.null(record$Built$R)) return(NA_character_)
    if (!identical(record$Built$OStype, .Platform$OS.type) ||
        (nzchar(record$Built$Platform) && record$Built$Platform != R.version$platform) ||
        record$Built$R[, 1:2] != getRversion()[, 1:2]) return(NA_character_)
    unname(record$DESCRIPTION[["Version"]])
  }, character(1))
}
