# Count-mode analysis shared by Shiny and the noninteractive runner.
# Paths passed here point to uncompressed featureCounts TSV and optional CSV/TSV metadata.
bulk_defaults <- function() {
  list(detection_cpm = 1, min_samples = 1L, pca_genes = 500L,
       display_scale = "logCPM", color_by = "none")
}

bulk_ids <- function(x, label) {
  if (!length(x) || anyNA(x) || any(!nzchar(trimws(x))) ||
      any(grepl("[\t\r\n]", x)) || anyDuplicated(x)) {
    stop(label, " must contain unique, nonempty identifiers without tabs or line breaks.")
  }
}

# Skip featureCounts' provenance comments only at the top of the file.
bulk_header <- function(path) {
  con <- file(path, "rt", encoding = "UTF-8")
  on.exit(close(con))
  skip <- 0L
  repeat {
    line <- readLines(con, n = 1L, warn = FALSE)
    if (!length(line)) stop("Missing table header in ", path)
    if (!startsWith(line, "#")) break
    skip <- skip + 1L
  }
  if (endsWith(line, "\t")) stop("Empty column name in ", path)
  header <- strsplit(line, "\t", fixed = TRUE)[[1L]]
  bulk_ids(header, "Table column names")
  list(names = header, skip = skip)
}

bulk_read_tsv <- function(path, header, drop = NULL) {
  # Character fields preserve identifiers such as 0003; malformed records must fail.
  issue <- NULL
  tab <- withCallingHandlers(data.table::fread(
    file = path, sep = "\t", skip = header$skip, header = TRUE, quote = "",
    drop = drop, colClasses = "character", na.strings = NULL, check.names = FALSE,
    strip.white = FALSE, encoding = "UTF-8", data.table = FALSE, fill = FALSE,
    showProgress = FALSE), warning = function(w) {
      issue <<- conditionMessage(w)
      invokeRestart("muffleWarning")
    })
  if (!is.null(issue)) stop(issue, call. = FALSE)
  expected <- if (is.null(drop)) header$names else header$names[-drop]
  if (!identical(names(tab), expected) || !nrow(tab)) stop("Empty or malformed TSV file: ", path)
  tab
}

bulk_integers <- function(x) {
  if (anyNA(x) || any(!grepl("^[0-9]+$", x))) {
    stop("Expected nonnegative integer counts; check input units and missing cells.")
  }
  x <- as.double(x)
  if (any(!is.finite(x)) || any(x >= 2^53)) stop("Counts exceed the exactly supported integer range.")
  x
}

bulk_import <- function(counts, samples = NULL, summary = NULL) {
  hdr <- bulk_header(counts)
  standard <- c("Geneid", "Chr", "Start", "End", "Strand", "Length")
  if (length(hdr$names) <= 6L || !identical(hdr$names[1:6], standard)) {
    stop("Expected a featureCounts TSV with Geneid, Chr, Start, End, Strand, Length and count columns.")
  }
  tab <- bulk_read_tsv(counts, hdr, drop = 2:6)
  bulk_ids(tab$Geneid, "Gene IDs")
  columns <- names(tab)[-1L]
  if (is.null(samples)) {
    mapping <- data.frame(sample_id = columns, count_column = columns)
  } else {
    mapping <- read.csv(samples, check.names = FALSE, colClasses = "character",
                        na.strings = character(), fileEncoding = "UTF-8-BOM", fill = FALSE)
    bulk_ids(names(mapping), "Sample sheet column names")
    if (!all(c("sample_id", "count_column") %in% names(mapping))) {
      stop("The CSV sample sheet requires sample_id and count_column.")
    }
    bulk_ids(mapping$count_column, "Sample sheet count_column")
    if (!setequal(columns, mapping$count_column)) {
      stop("Sample sheet count_column values must match the complete set of count headers exactly.")
    }
    mapping <- mapping[match(columns, mapping$count_column), , drop = FALSE]
  }
  bulk_ids(mapping$sample_id, "Sample IDs")
  if (any(mapping$sample_id %in% c("gene_id", "sample_id"))) {
    stop("The IDs 'gene_id' and 'sample_id' are reserved in exported tables. Supply distinct sample IDs.")
  }
  rownames(mapping) <- mapping$sample_id
  values <- as.matrix(as.data.frame(lapply(tab[columns], bulk_integers), check.names = FALSE))
  dimnames(values) <- list(tab$Geneid, mapping$sample_id)
  totals <- colSums(values)
  if (any(totals == 0)) stop("Zero-count libraries have no CPM denominator: ",
                             paste(names(totals)[totals == 0], collapse = ", "))
  if (any(totals >= 2^53)) stop("Library totals exceed the exactly supported integer range.")
  assigned <- NULL
  if (!is.null(summary)) {
    stat <- bulk_read_tsv(summary, bulk_header(summary))
    if (names(stat)[1L] != "Status" || !setequal(names(stat)[-1L], columns) ||
        sum(stat$Status == "Assigned") != 1L) {
      stop("Summary requires exactly one Assigned row and a matching set of count headers.")
    }
    assigned <- bulk_integers(unlist(stat[stat$Status == "Assigned", columns, drop = FALSE],
                                     use.names = FALSE))
    names(assigned) <- mapping$sample_id
    if (any(totals != assigned)) {
      stop("Assigned totals differ from gene-count column sums for ",
           paste(names(totals)[totals != assigned], collapse = ", "),
           ". Check the summary and counting mode.")
    }
  }
  list(counts = values, samples = mapping, assigned = assigned)
}

bulk_number <- function(x, name, integer = FALSE) {
  if (!is.numeric(x) || length(x) != 1L || !is.finite(x) || x < 0) {
    stop(name, " must be a single finite nonnegative number.")
  }
  if (integer && (x < 1 || x != floor(x) || x > .Machine$integer.max)) {
    stop(name, " must be a positive integer.")
  }
}

bulk_settings <- function(settings, imported) {
  defaults <- bulk_defaults()
  if (!is.list(settings) || (length(settings) && is.null(names(settings))) ||
      anyDuplicated(names(settings)) || length(setdiff(names(settings), names(defaults)))) {
    stop("Expected an object with supported count-explorer settings.")
  }
  defaults[names(settings)] <- settings
  bulk_number(defaults$detection_cpm, "detection_cpm")
  bulk_number(defaults$min_samples, "min_samples", TRUE)
  bulk_number(defaults$pca_genes, "pca_genes", TRUE)
  if (defaults$min_samples > ncol(imported$counts)) stop("min_samples exceeds the number of libraries.")
  if (!identical(defaults$display_scale, "CPM") && !identical(defaults$display_scale, "logCPM")) {
    stop("display_scale must be CPM or logCPM.")
  }
  if (!is.character(defaults$color_by) || length(defaults$color_by) != 1L ||
      !defaults$color_by %in% c("none", names(imported$samples))) {
    stop("color_by must be 'none' or a column from the mapped sample sheet.")
  }
  defaults
}

bulk_expression <- function(imported) {
  counts <- imported$counts
  sizes <- colSums(counts)
  factors <- if (ncol(counts) == 1L) setNames(1, colnames(counts)) else {
    withCallingHandlers(edgeR::normLibSizes(counts, method = "TMM"),
      warning = function(w) stop("TMM normalization could not be estimated: ",
                                 conditionMessage(w), call. = FALSE))
  }
  effective <- sizes * factors
  if (any(!is.finite(effective) | effective <= 0)) stop("Invalid effective library size from TMM.")
  list(cpm = edgeR::cpm(counts, lib.size = effective),
       logcpm = edgeR::cpm(counts, lib.size = effective, log = TRUE, prior.count = 2),
       factors = factors, library_sizes = sizes)
}

bulk_display <- function(cpm, detection_cpm, min_samples) {
  bulk_number(detection_cpm, "detection_cpm")
  bulk_number(min_samples, "min_samples", TRUE)
  if (min_samples > ncol(cpm)) stop("min_samples exceeds the number of libraries.")
  rowSums(cpm >= detection_cpm) >= min_samples
}

bulk_pca <- function(logcpm, limit) {
  if (ncol(logcpm) < 2L) return(list(status = "PCA requires at least two libraries."))
  means <- rowMeans(logcpm)
  variances <- rowSums((logcpm - means)^2) / (ncol(logcpm) - 1)
  variable <- which(variances > (16 * .Machine$double.eps * pmax(1, abs(means)))^2)
  if (!length(variable)) return(list(status = "No genes have measurable between-library variation."))
  # Ties retain input gene order. Keep only numerically supported centered axes.
  rows <- head(variable[order(variances[variable], decreasing = TRUE, method = "radix")], limit)
  fit <- stats::prcomp(t(logcpm[rows, , drop = FALSE]), center = TRUE, scale. = FALSE,
                       tol = sqrt(.Machine$double.eps))
  scores <- fit$x
  # Resolve the arbitrary sign for each axis by its largest absolute loading.
  for (axis in seq_len(ncol(scores))) {
    anchor <- which.max(abs(fit$rotation[, axis]))
    if (fit$rotation[anchor, axis] < 0) scores[, axis] <- -scores[, axis]
  }
  components <- seq_len(ncol(scores))
  variance <- data.frame(axis = colnames(scores),
                         percent = 100 * fit$sdev[components]^2 / sum(fit$sdev^2))
  list(status = "Available", scores = scores, variance = variance,
       features = data.frame(gene_id = rownames(logcpm)[rows], logCPM_variance = variances[rows]))
}

bulk_frame <- function(mat, id_name) {
  ids <- rownames(mat)
  if (!nrow(mat)) ids <- character()
  result <- data.frame(ids, as.data.frame(mat, optional = TRUE), check.names = FALSE)
  names(result)[1L] <- id_name
  result
}

# fwrite's numeric representation carries 15 significant digits. Preserve the
# full decimal representation even for integer-valued doubles above that range.
bulk_exact_column <- function(x) {
  if (any(x >= 1e15)) sprintf("%.0f", x) else x
}

bulk_analyze <- function(imported, settings, out_dir, expression = NULL) {
  settings <- bulk_settings(settings, imported)
  if (is.null(expression)) expression <- bulk_expression(imported)
  counts <- imported$counts
  samples <- imported$samples
  cpm <- expression$cpm
  logcpm <- expression$logcpm
  n <- ncol(cpm)
  displayed <- bulk_display(cpm, settings$detection_cpm, settings$min_samples)
  expressed <- rowSums(counts > 0) > 0L
  qc_log <- logcpm[expressed, , drop = FALSE]
  pca <- bulk_pca(qc_log, settings$pca_genes)
  norm_label <- if (n == 1L) "Library size (single library)" else "TMM"
  files <- list()
  for (subdir in c("tables", "figures")) dir.create(file.path(out_dir, subdir), showWarnings = FALSE)
  save_table <- function(key, table) {
    path <- file.path("tables", paste0(key, ".tsv"))
    data.table::fwrite(table, file.path(out_dir, path), sep = "\t", eol = "\n", na = "NA")
    files[[key]] <<- path
  }
  theme <- ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(panel.grid.minor = ggplot2::element_blank(),
                   panel.grid.major.y = ggplot2::element_blank(),
                   plot.title = ggplot2::element_text(face = "bold", size = 17),
                   plot.title.position = "plot",
                   legend.position = "bottom")
  save_plot <- function(key, plot, height = 5) {
    path <- file.path("figures", paste0(key, ".png"))
    plot <- plot + theme
    if (key == "correlation_plot") {
      plot <- plot + ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
    }
    ggplot2::ggsave(file.path(out_dir, path), plot, device = ragg::agg_png,
                    width = 9, height = height, units = "in", dpi = 135, bg = "white")
    files[[key]] <<- path
  }

  label <- samples$sample_id
  if (any(nchar(label, type = "width") > 36L)) label <- paste("Library", seq_len(n))
  group <- rep("Library", n)
  grouped <- settings$color_by != "none"
  if (grouped) {
    group <- samples[[settings$color_by]]
    group[is.na(group) | group == ""] <- "(missing)"
  }
  qc <- data.frame(sample_id = samples$sample_id, plot_label = label,
                   library_size = expression$library_sizes, norm_factor = expression$factors,
                   effective_library_size = expression$library_sizes * expression$factors,
                   nonzero_genes = colSums(counts > 0),
                   detected_genes = colSums(cpm >= settings$detection_cpm), row.names = NULL)
  if (!is.null(imported$assigned)) qc$assigned <- unname(imported$assigned)
  save_table("mapping", samples)
  qc_export <- qc
  for (column in intersect(c("library_size", "assigned"), names(qc))) {
    qc_export[[column]] <- bulk_exact_column(qc[[column]])
  }
  save_table("qc", qc_export)
  raw <- bulk_frame(counts, "gene_id")
  raw[-1L] <- lapply(raw[-1L], bulk_exact_column)
  save_table("raw", raw)
  save_table("cpm", bulk_frame(cpm, "gene_id"))
  save_table("logcpm", bulk_frame(logcpm, "gene_id"))
  view <- if (settings$display_scale == "CPM") cpm else logcpm
  save_table("display", bulk_frame(view[displayed, , drop = FALSE], "gene_id"))

  y <- factor(label, levels = rev(label))
  group_fill <- if (grouped) {
    ggplot2::scale_fill_discrete(name = settings$color_by)
  } else ggplot2::scale_fill_manual(values = "#14776f", guide = "none")
  dims <- min(12, max(4, 2 + 0.38 * n))
  bars <- data.frame(y, group, millions = qc$library_size / 1e6)
  save_plot("library_plot", ggplot2::ggplot(bars, ggplot2::aes(millions, y, fill = group)) +
              ggplot2::geom_col(width = 0.7) + group_fill +
              ggplot2::labs(title = "Library sizes", subtitle = "Sum of raw gene counts in each library",
                            x = "Millions of counts", y = NULL), dims)

  # Tukey boxplots over the shared gene set. Whiskers end at observations within 1.5 IQR.
  boxes <- t(vapply(seq_len(n), function(i) grDevices::boxplot.stats(qc_log[, i],
                       do.conf = FALSE, do.out = FALSE)$stats, numeric(5)))
  boxes <- data.frame(y, group, setNames(as.data.frame(boxes), c("lo", "q1", "median", "q3", "hi")))
  save_plot("distribution_plot", ggplot2::ggplot(boxes,
              ggplot2::aes(y = y, xmin = lo, xlower = q1, xmiddle = median, xupper = q3, xmax = hi,
                           fill = group)) +
              ggplot2::geom_boxplot(stat = "identity", orientation = "y", width = 0.58) + group_fill +
              ggplot2::labs(title = "Expression distributions",
                            subtitle = paste(sum(expressed), "genes with a nonzero count in any library"),
                            x = paste0("log2 CPM  (", norm_label, ", prior count 2)"), y = NULL), dims)

  correlation_status <- "Sample correlation requires at least two libraries."
  if (n > 1L) {
    correlation_status <- "Fewer than two genes or no measurable within-library variation."
    if (nrow(qc_log) > 1L) {
      correlations <- suppressWarnings(stats::cor(qc_log, method = "pearson"))
      constant <- apply(qc_log, 2L, function(x) diff(range(x)) <=
                        16 * .Machine$double.eps * max(1, abs(x)))
      correlations[constant, ] <- NA_real_
      correlations[, constant] <- NA_real_
      if (any(is.finite(correlations[lower.tri(correlations)]))) {
        correlation_status <- if (anyNA(correlations)) {
          "Partial: grey cells indicate undefined correlations for constant libraries."
        } else "Available"
        save_table("correlation", bulk_frame(correlations, "sample_id"))
        grid <- expand.grid(col = label, row = rev(label), KEEP.OUT.ATTRS = FALSE)
        grid$r <- as.vector(correlations[, rev(seq_len(n)), drop = FALSE])
        heat <- ggplot2::ggplot(grid, ggplot2::aes(col, row, fill = r)) + ggplot2::geom_tile() +
          ggplot2::scale_fill_gradient2(low = "#984a37", mid = "#f8f6ed", high = "#126964",
                                        limits = c(-1, 1), na.value = "grey85", name = "Pearson r") +
          ggplot2::coord_equal() +
          ggplot2::labs(title = "Sample correlations", subtitle = paste(sum(expressed),
                        "nonzero genes across libraries, normalized log2 CPM"), x = NULL, y = NULL)
        if (n <= 10L) {
          grid$value <- ifelse(is.na(grid$r), "", sprintf("%.2f", grid$r))
          heat <- heat + ggplot2::geom_text(data = grid, ggplot2::aes(label = value,
                      color = abs(r) > 0.65), size = 3.4, show.legend = FALSE) +
            ggplot2::scale_color_manual(values = c("FALSE" = "#182828", "TRUE" = "white"))
        }
        save_plot("correlation_plot", heat, min(12, max(6.5, dims)))
      }
    }
  }

  if (!is.null(pca$scores)) {
    save_table("pca_scores", bulk_frame(pca$scores, "sample_id"))
    save_table("pca_variance", pca$variance)
    save_table("pca_features", pca$features)
    two_axes <- ncol(pca$scores) >= 2L
    pts <- data.frame(label, group, x = pca$scores[, 1L],
                      y = if (two_axes) pca$scores[, 2L] else 0)
    axis_labels <- sprintf("%s (%.1f%%)", pca$variance$axis, pca$variance$percent)
    plot <- ggplot2::ggplot(pts, ggplot2::aes(x, y, color = group)) +
      ggplot2::geom_point(size = 3) +
      ggrepel::geom_text_repel(ggplot2::aes(label = label), size = 3, max.overlaps = Inf,
                              seed = 1L, max.time = 0.5, show.legend = FALSE) +
      ggplot2::scale_x_continuous(expand = ggplot2::expansion(mult = 0.18)) +
      ggplot2::labs(title = "Principal components", subtitle = paste(nrow(pca$features),
                    "variable genes, centered normalized log2 CPM"), x = axis_labels[1L],
                    y = if (two_axes) axis_labels[2L] else NULL, color = settings$color_by)
    if (!two_axes) plot <- plot + ggplot2::scale_y_continuous(breaks = NULL)
    if (!grouped) plot <- plot + ggplot2::scale_color_manual(values = "#14776f", guide = "none")
    save_plot("pca_plot", plot)
  }
  list(genes = nrow(counts), samples = n, displayed_genes = sum(displayed),
       qc_genes = sum(expressed), pca_genes = if (is.null(pca$features)) 0L else nrow(pca$features),
       pca_axes = if (is.null(pca$scores)) 0L else ncol(pca$scores),
       normalization = norm_label, prior_count = 2,
       status = list(pca = pca$status, correlation = correlation_status), files = files)
}
