# Configure the project library, including for child sessions launched elsewhere.
local({
  root <- if (file.exists("environment/runtime.R")) "." else Sys.getenv("TRANSCRIPTOMICS_ROOT")
  startup <- file.path(root, "environment", "runtime.R")
  if (file.exists(startup)) source(startup, local = TRUE)
})
