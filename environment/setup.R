# From the project root: Rscript --vanilla environment/setup.R
# Restore exact package records into the private library for this OS and R version.
project_library <- file.path(getwd(), "environment", "R-library")
if (!dir.exists(project_library) && !dir.create(project_library, recursive = TRUE)) {
  stop("Could not create the private package library")
}
source("environment/runtime.R")
options(repos = c(CRAN = "https://cloud.r-project.org"), timeout = 300)
Sys.setenv(RENV_PATHS_ROOT = file.path(project_root, "environment", ".renv-cache"),
           RENV_CONFIG_CACHE_ENABLED = "FALSE", RENV_CONFIG_SANDBOX_ENABLED = "FALSE",
           RENV_CONFIG_CONSENT = "TRUE", RENV_CONFIG_AUTOLOADER_ENABLED = "FALSE")
bootstrap_version <- "1.2.4"
ready <- identical(unname(project_package_versions("renv")), bootstrap_version)
if (!ready) {
  archive <- paste0("renv_", bootstrap_version, ".tar.gz")
  urls <- paste0(getOption("repos")[["CRAN"]], "/src/contrib/",
                 c(archive, paste0("Archive/renv/", archive)))
  tarball <- tempfile(fileext = ".tar.gz")
  downloaded <- FALSE
  for (url in urls) {
    downloaded <- tryCatch(utils::download.file(url, tarball, mode = "wb") == 0,
                           error = function(e) FALSE)
    if (downloaded) break
  }
  if (!downloaded) stop("Could not download the pinned renv bootstrap ", bootstrap_version)
  utils::install.packages(tarball, repos = NULL, type = "source", lib = project_library)
}
if (!requireNamespace("renv", quietly = TRUE) ||
    as.character(getNamespaceVersion("renv")) != bootstrap_version) stop("renv bootstrap failed")
lock_path <- file.path(project_root, "environment", "renv.lock")
lock <- renv::lockfile_read(lock_path)
if (lock$Packages$renv$Version != bootstrap_version) stop("Bootstrap version differs from the lock")
if (as.character(getRversion()) != lock$R$Version) stop("Use R ", lock$R$Version, " for this lock")
expected <- vapply(lock$Packages, function(record) record$Version, character(1))
installed <- project_package_versions(names(expected))
missing_or_changed <- names(expected)[is.na(installed) | installed != expected]
if (length(missing_or_changed)) {
  renv::restore(project = project_root, library = project_library, lockfile = lock_path,
                packages = missing_or_changed, rebuild = missing_or_changed,
                prompt = FALSE, transactional = TRUE)
} else {
  message("The project library already matches the locked package versions.")
}
source("scripts/00_check_environment.R")
