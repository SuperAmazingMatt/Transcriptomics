# Server implementation used by both live browser sessions and Shiny integration checks.
explorer_server <- function(input, output, session) {
  current_run <- reactiveVal(NULL)
  history <- reactiveVal("Ready.")
  open_message <- reactiveVal("")
  page <- reactiveVal(1L)
  field_names <- c(detection_cpm = "Detection threshold", min_samples = "Minimum samples",
                   pca_genes = "Maximum PCA genes", display_scale = "Expression scale", color_by = "Plot color")
  setting_effects <- c(detection_cpm = "expression display and per-library detection counts", min_samples = "expression display",
                       pca_genes = "PCA", display_scale = "expression display", color_by = "QC figures")
  request_files <- reactive({
    req(input$source_mode)
    if (input$source_mode == "bms") {
      validate(need(!is.null(bms_demo), "The local teaching dataset is unavailable."))
      return(bms_demo$files)
    }
    validate(need(!is.null(input$counts_file), "Upload a featureCounts matrix to preview this run."))
    Filter(Negate(is.null), list(counts = input$counts_file$datapath,
                                samples = input$samples_file$datapath, summary = input$summary_file$datapath))
  })
  # Cache import and normalized matrices across all setup previews in this session.
  imported <- reactive({
    files <- request_files()
    tryCatch(do.call(bulk_import, files), error = function(e) validate(need(FALSE, conditionMessage(e))))
  })
  normalized <- reactive({
    data <- imported()
    tryCatch(bulk_expression(data), error = function(e) validate(need(FALSE, conditionMessage(e))))
  })
  proposed_settings <- reactive({
    chosen <- lapply(names(defaults), function(key) {
      value <- input[[key]]
      if (is.null(value)) defaults[[key]] else value
    })
    names(chosen) <- names(defaults)
    data <- imported()
    tryCatch(bulk_settings(chosen, data), error = function(e) validate(need(FALSE, conditionMessage(e))))
  })
  observeEvent(imported(), {
    choices <- c("Uniform" = "none", names(imported()$samples))
    previous <- isolate(input$color_by)
    updateSelectInput(session, "color_by", choices = choices,
                      selected = if (length(previous) && previous %in% choices) previous else "none")
  })
  output$mapping_status <- renderText({
    data <- imported()
    method <- if (is.null(request_files()$samples)) "Header IDs serve as sample IDs." else "Sample sheet matched by exact count header."
    paste(fmt_n(nrow(data$counts)), "genes ·", ncol(data$counts), "libraries.", method)
  })
  output$mapping <- renderTable(imported()$samples, striped = TRUE)
  output$mapping_csv <- downloadHandler("sample-mapping.csv", function(file) {
    utils::write.csv(imported()$samples, file, row.names = FALSE)
  })
  output$preview <- renderUI({
    settings <- proposed_settings()
    cpm <- normalized()$cpm
    retained <- sum(bulk_display(cpm, settings$detection_cpm, settings$min_samples))
    changed <- names(defaults)[vapply(names(defaults), function(key) {
      !isTRUE(all.equal(defaults[[key]], settings[[key]]))
    }, logical(1))]
    tagList(
      p(class = "stat-line", strong(fmt_n(retained)), " of ", fmt_n(nrow(cpm)), " genes in view"),
      p(class = "muted", "Complete raw counts, CPM and log₂ CPM will include all genes."),
      if (length(changed)) tags$ul(class = "changes", lapply(changed, function(key) {
        tags$li(paste0(field_names[[key]], " · ", defaults[[key]], " → ", settings[[key]], " (", setting_effects[[key]], ")"))
      })) else p(class = "muted", "Using preset defaults."))
  })
  output$save_preset <- downloadHandler("bulk-expression-settings.json", function(file) {
    jsonlite::write_json(list(preset = "bulk-expression-v1", settings = proposed_settings()),
                         file, auto_unbox = TRUE, pretty = TRUE)
  })
  observeEvent(input$preset_file, {
    tryCatch({
      preset <- jsonlite::read_json(input$preset_file$datapath)
      if (!identical(preset$preset, "bulk-expression-v1") || !is.list(preset$settings)) {
        stop("Choose a bulk-expression-v1 settings file.")
      }
      settings <- bulk_settings(preset$settings, imported())
      for (id in c("detection_cpm", "min_samples", "pca_genes")) updateNumericInput(session, id, value = settings[[id]])
      for (id in c("display_scale", "color_by")) updateSelectInput(session, id, selected = settings[[id]])
      showNotification("Loaded saved settings. Review the run preview.", type = "message")
    }, error = function(e) showNotification(conditionMessage(e), type = "error"))
  })

  open_results <- function(path) {
    run <- open_bulk_run(path)
    settings <- run$index$settings
    current_run(run)
    updateTextInput(session, "run_dir", value = run$dir)
    updateNumericInput(session, "view_cpm", value = settings$detection_cpm)
    updateNumericInput(session, "view_samples", value = settings$min_samples, max = run$index$summary$samples)
    updateSelectInput(session, "view_scale", selected = settings$display_scale)
    updateTextInput(session, "query", value = "")
    page(1L)
    paths <- unlist(run$index$outputs, use.names = TRUE)
    figures <- intersect(c("library_plot", "distribution_plot", "correlation_plot", "pca_plot"), names(paths))
    figure_labels <- c(library_plot = "Library sizes", distribution_plot = "Expression distributions",
                       correlation_plot = "Sample correlations", pca_plot = "Principal components")
    updateSelectInput(session, "figure", choices = stats::setNames(figures, figure_labels[figures]))
    updateSelectInput(session, "artifact", choices = stats::setNames(names(paths), unname(paths)))
    open_message(paste("Opened", basename(run$dir)))
    updateTabsetPanel(session, "workspace_tab", "results")
  }
  observeEvent(input$run, {
    updateTabsetPanel(session, "workspace_tab", "log")
    history(character())
    log_stage <- function(stage) history(c(isolate(history()), paste(format(Sys.time(), "%H:%M:%S"), stage)))
    tryCatch(withProgress(message = "Running expression analysis", value = 0, {
      log_stage("Checking inputs and settings")
      settings <- proposed_settings()
      files <- request_files()
      if (identical(input$source_mode, "bms")) {
        spec <- bms_demo$spec
        profile <- bms_demo$profile
      } else {
        spec <- list(schema_version = 1L, preset = "bulk-expression-v1",
                     dataset = list(id = input$dataset_id, species = input$species,
                                    assembly = input$assembly, annotation = input$annotation,
                                    notes = "User-supplied featureCounts matrix."))
        profile <- list(schema_version = 1L, output_root = "results")
      }
      spec$settings <- settings
      spec$inputs <- as.list(stats::setNames(names(files), names(files)))
      profile$paths <- files
      profile$output_root <- bulk_path(profile$output_root)
      path <- run_bulk(spec, profile, progress = function(stage) {
        log_stage(stage)
        setProgress(detail = stage)
      }, entry_point = "shiny")
      open_results(path)
      log_stage(paste("Completed", basename(path)))
      setProgress(value = 1)
    }), error = function(e) {
      msg <- conditionMessage(e)
      if (!nzchar(msg)) msg <- "Complete the required inputs and review the setup preview."
      log_stage(paste("Stopped.", msg))
      showNotification(msg, type = "error", duration = NULL)
    })
  })
  output$run_log <- renderText(paste(history(), collapse = "\n"))
  observeEvent(input$reopen, {
    tryCatch({
      if (!nzchar(trimws(input$run_dir))) stop("Enter a completed run folder.")
      open_results(bulk_path(trimws(input$run_dir)))
    }, error = function(e) open_message(paste("Could not open run.", conditionMessage(e))))
  })
  output$open_status <- renderText(open_message())
  output$has_result <- reactive(!is.null(current_run()))
  outputOptions(output, "has_result", suspendWhenHidden = FALSE)
  output$result_header <- renderUI({
    run <- req(current_run())
    result <- run$index
    with(result$summary, tagList(
      h2(class = "result-title", result$dataset$id),
      p(class = "muted", paste(fmt_n(genes), "genes ·", samples, "libraries ·",
                               fmt_n(displayed_genes), "genes in saved display"))))
  })
  artifact_path <- function(key) {
    run <- req(current_run())
    req(length(key) == 1L, key %in% names(run$index$outputs))
    file.path(run$dir, run$index$outputs[[key]])
  }
  read_expression <- function(key) {
    # Preserve gene IDs such as 0001 when fread infers column types.
    data.table::fread(artifact_path(key), sep = "\t", check.names = FALSE, data.table = FALSE,
                      colClasses = list(character = "gene_id"), na.strings = NULL)
  }
  cpm_table <- reactive(read_expression("cpm"))
  log_table <- reactive(read_expression("logcpm"))
  view_rows <- reactive({
    tab <- cpm_table()
    req(input$view_cpm, input$view_samples)
    validate(need(is.finite(input$view_cpm) && input$view_cpm >= 0, "Enter a finite detection threshold of zero or more."),
             need(is.finite(input$view_samples) && input$view_samples == floor(input$view_samples) &&
                  input$view_samples >= 1 && input$view_samples < ncol(tab), "Choose a whole sample count between 1 and the number of libraries."))
    keep <- bulk_display(as.matrix(tab[-1]), input$view_cpm, input$view_samples)
    if (isTruthy(input$query)) keep <- keep & grepl(tolower(input$query), tolower(tab$gene_id), fixed = TRUE)
    which(keep)
  })
  observeEvent(list(input$query, input$view_cpm, input$view_samples), page(1L), ignoreNULL = FALSE, priority = 5)
  page_size <- 20L
  page_count <- reactive(max(1L, ceiling(length(view_rows()) / page_size)))
  observeEvent(input$previous_page, page(max(1L, page() - 1L)))
  observeEvent(input$next_page, page(min(page_count(), page() + 1L)))
  output$view_status <- renderText({
    scale <- if (identical(input$view_scale, "CPM")) "CPM" else "log₂ CPM"
    normalization <- current_run()$index$summary$normalization
    paste0(fmt_n(length(view_rows())), " matching genes · Page ", page(), " of ", page_count(),
      " · ", scale, " · ", normalization, ". View changes leave saved exports intact.")
  })
  output$expression_view <- renderTable({
    ids <- view_rows()
    rows <- head(ids[seq_along(ids) > (page() - 1L) * page_size], page_size)
    tab <- if (identical(input$view_scale, "CPM")) cpm_table() else log_table()
    tab[rows, , drop = FALSE]
  }, striped = TRUE, digits = 3)
  output$qc_table <- renderTable({
    data.table::fread(artifact_path("qc"), data.table = FALSE, colClasses = list(character = "sample_id"))
  }, striped = TRUE, digits = 4)
  output$qc_image <- renderImage({
    path <- artifact_path(input$figure)
    list(src = path, contentType = "image/png", alt = paste("Sample QC figure", basename(path)))
  }, deleteFile = FALSE)
  output$report_html <- downloadHandler("expression-report.html", function(file) {
    if (!file.copy(artifact_path("report"), file)) stop("Could not export the report.")
  })
  output$artifact_file <- downloadHandler(function() basename(artifact_path(input$artifact)), function(file) {
    if (!file.copy(artifact_path(input$artifact), file)) stop("Could not export the selected file.")
  })
}
