# Start from the project root with shiny::runApp("app") after environment activation.
app_root <- if (file.exists("environment/runtime.R")) "." else ".."
if (!file.exists(file.path(app_root, "environment/runtime.R"))) app_root <- Sys.getenv("TRANSCRIPTOMICS_ROOT")
Sys.setenv(TRANSCRIPTOMICS_ROOT = normalizePath(app_root, winslash = "/", mustWork = TRUE))
source(file.path(app_root, "environment/runtime.R"), local = TRUE)
source(file.path(project_root, "scripts/bulk_run.R"), local = TRUE)
library(shiny)
options(shiny.maxRequestSize = 512 * 1024^2)

read_config <- function(name) bulk_read_json(file.path(project_root, "config", name))
bms_configs <- c("bms_run.json", "local_profile.json")
bms_demo <- if (all(file.exists(file.path(project_root, "config", bms_configs)))) {
  tryCatch({
    spec <- read_config("bms_run.json")
    profile <- read_config("local_profile.json")
    config <- bulk_config(spec, profile)
    list(spec = spec, profile = profile, files = config$paths)
  }, error = function(e) NULL)
}
source_choices <- c(if (!is.null(bms_demo)) c("BMS mouse T-cell teaching counts" = "bms"),
                    "Upload featureCounts files" = "upload")
fmt_n <- function(x) format(x, big.mark = ",", scientific = FALSE, trim = TRUE)
field <- function(id, label, help, control) {
  div(class = "field",
    tags$label(`for` = id, label),
    tags$details(class = "field-help",
      tags$summary(`aria-label` = paste("Help for", label), "?"),
      div(class = "help-copy", help)),
    control)
}
panel <- function(title, ...) div(class = "work-panel", h2(title), ...)
scroll_table <- function(id) div(class = "scroll-table", tableOutput(id))
num_field <- function(id, label, help, value, min, step = 1) {
  field(id, label, help, numericInput(id, NULL, value = value, min = min, step = step))
}
defaults <- bulk_defaults()
scale_choices <- c("Log₂ CPM" = "logCPM", "CPM" = "CPM")
threshold_help <- "Default 1 count per million. CPM uses TMM effective library sizes for multiple libraries and the total count for a single library. Raise the threshold to focus on stronger signals. The saved setting also determines the detected-gene counts in sample QC."
samples_help <- "Default 1 library. Choose 3 to show a gene only when it meets the CPM threshold in at least three libraries. This changes the expression view."
scale_help <- "Default log₂ CPM. The log scale uses a prior count of 2 scaled to library size and makes large differences easier to compare. CPM shows normalized counts per million on a linear scale. This changes the displayed values."
source(file.path(project_root, "app/interface.R"), local = TRUE)
source(file.path(project_root, "app/explorer_server.R"), local = TRUE)
shinyApp(ui = explorer_ui, server = explorer_server)
