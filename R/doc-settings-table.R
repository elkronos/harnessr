# doc-settings-table.R: every setting of every stage in one table, built
# from what declares them: the spec schemas, the option rules, the stages'
# function arguments and their help pages. Nothing here repeats a default or
# a description that is declared elsewhere, so the table cannot drift from
# the code; what is declared here is only what has no other home: which
# arguments are inputs rather than settings, the tier and evidence of the
# arguments the walkthroughs cover, and which guide section explains each.

#' The functions whose arguments are settings of a stage, and the arguments
#' of each that are inputs (the data a call works on) rather than settings.
#' @noRd
.gr_stage_functions <- list(
  gr_read_many = list(stage = "read", inputs = c("sources", "question", "client", "trace")),
  gr_screen = list(stage = "screen", inputs = c("sources", "protocol", "question", "include",
                                                "exclude", "client", "trace")),
  gr_reference = list(stage = "screen", inputs = c("screening", "path")),
  gr_calibrate = list(stage = "screen", inputs = c("screening", "reference")),
  gr_screen_sample_size = list(stage = "screen", inputs = character(0)),
  gr_stop_test = list(stage = "screen", inputs = "screened_order"),
  gr_extract = list(stage = "extract", inputs = c("sources", "fields", "goal", "client",
                                                  "trace")),
  gr_claims = list(stage = "synthesise", inputs = c("extraction", "question", "protocol",
                                                    "client", "trace", "bib", "moderators")),
  gr_outline = list(stage = "synthesise", inputs = c("claims", "question", "client", "trace")),
  gr_gaps = list(stage = "synthesise", inputs = c("claims", "extraction", "bib")),
  gr_synthesise = list(stage = "synthesise",
                       inputs = c("extraction", "protocol", "outline", "question", "client",
                                  "bib", "claims", "gaps", "trace")),
  hr_benchmark = list(stage = "evaluate", inputs = c("arms", "reference", "client")),
  hr_report = list(stage = "evaluate", inputs = c("bench", "registration")),
  hr_judge = list(stage = "evaluate", inputs = c("candidates", "client", "reference", "rubric",
                                                 "schema", "trace")),
  gr_compare = list(stage = "evaluate", inputs = c("source", "question", "client", "correct"))
)

#' The arguments of those functions most runs set, as "function.argument".
#' Every other argument is advanced.
#' @noRd
.gr_stage_basic <- c(
  "gr_read_many.recipe", "gr_read_many.store", "gr_read_many.max_total_usd",
  "gr_screen.recipe", "gr_screen.screen_tokens", "gr_screen.max_total_usd",
  "gr_reference.n", "gr_reference.of",
  "gr_calibrate.recall_target", "gr_calibrate.conf",
  "gr_screen_sample_size.recall_target", "gr_screen_sample_size.conf",
  "gr_screen_sample_size.prevalence", "gr_stop_test.target",
  "gr_extract.recipe", "gr_extract.resolve", "gr_extract.require_quote",
  "gr_claims.model", "gr_outline.max_sections",
  "gr_synthesise.model", "gr_synthesise.coherence", "gr_synthesise.cite_style",
  "hr_benchmark.runs", "hr_benchmark.scorer", "hr_benchmark.governor",
  "hr_report.conf", "hr_report.method",
  "hr_judge.mode", "hr_judge.model", "hr_judge.orders",
  "gr_compare.recipes")

#' Where the defaults of the stage arguments the walkthroughs cover come
#' from, as "function.argument". The others declare none.
#' @noRd
.gr_stage_evidence <- list(
  gr_screen.screen_tokens = ev_untested(paste0(
    "Not a tuned value: NULL shows as much of each document as the model's context allows.")),
  gr_calibrate.recall_target = ev_untested(paste0(
    "A target reviews commonly set; a choice for the review, not a tuned value.")),
  gr_calibrate.conf = ev_untested("The conventional 95% level; a choice, not a tuned value."),
  gr_calibrate.max_width = ev_untested("Ten percentage points, set when the rule was written."),
  gr_screen_sample_size.recall_target = ev_untested(paste0(
    "A target reviews commonly set; a choice for the review, not a tuned value.")),
  gr_screen_sample_size.conf = ev_untested(
    "The conventional 95% level; a choice, not a tuned value."),
  gr_extract.resolve = ev_untested(paste0(
    "\"first\" costs nothing and records each disagreement; not compared with \"model\" ",
    "or \"vote\".")),
  gr_screen.criteria_schema = ev_untested(paste0(
    "\"decision\" is the reply screening was written with; not compared with ",
    "\"per_criterion\".")),
  gr_screen.samples = ev_untested("One request per document, as before; not compared."),
  gr_screen.sample_rule = ev_untested(paste0(
    "\"include_if_any\" so that no study one draw would keep is lost; not compared with ",
    "\"majority\".")),
  gr_extract.agreement_columns = ev_untested(
    "Off, so the table keeps the columns it had; it changes no request."),
  gr_extract.require_quote = ev_untested(paste0(
    "Off, so no extracted value is thrown away unasked; n_unverified counts the same ",
    "values without dropping them.")),
  gr_synthesise.coherence = ev_untested(paste0(
    "Off: each pass is a request and a chance for a model to change finished prose.")),
  gr_synthesise.coherence_rounds = ev_untested(paste0(
    "One round per pass, as before the setting existed. paper-orchestra runs up to 3 ",
    "rounds, with no recorded evidence for that number.")),
  gr_synthesise.figure_bands = ev_untested("Set when the check of figures was written."),
  gr_synthesise.prominence = ev_untested("Thirds, set when claims were added."),
  gr_claims.unverified = ev_untested(paste0(
    "\"exclude\", so a claim rests on what the documents were found to say; not compared ",
    "with \"include\"."))
)

#' The entries of an ingest spec's `cleaner_opts` the built-in cleaners
#' read, with their defaults. references_after() and drop_running_heads()
#' hold the same values; a test checks they agree.
#' @noRd
.gr_cleaner_opts <- list(
  references_after = list(
    default = 0.4, help = paste0(
      "For the references cleaner: the share of the text after which a References heading ",
      "ends the text."),
    evidence = ev_untested("Set when the references cleaner was written; not compared.")),
  header_max_chars = list(
    default = 80L, help = paste0(
      "For the headers_footers cleaner: the longest line that can be taken for a running ",
      "head or foot."),
    evidence = ev_untested("Set when the headers_footers cleaner was written.")),
  header_min_repeats = list(
    default = 3L, help = paste0(
      "For headers_footers: how many times a line must recur to be taken for a running ",
      "head; values below 3 are read as 3."),
    evidence = ev_untested("Set when the headers_footers cleaner was written.")))

#' What each `layout_opts` entry does; its default is drop_running_lines()'s.
#' @noRd
.gr_layout_opt_help <- c(
  depth = "Lines at each edge of a PDF page that are candidates for a running head or foot.",
  share = "The share of pages a line must recur on to be dropped as a running head or foot.",
  min_pages = paste0("The fewest pages a document needs before any line is dropped, and the ",
                     "fewest a line must recur on."),
  max_chars = "The longest line, in characters, that can be a running head or foot.",
  max_words = paste0("Above this many words, a numbered line must carry its number where a ",
                     "page number is set."))

#' The options most sessions set. Every other option is advanced.
#' @noRd
.gr_option_basic <- c("model", "verbose", "max_cost_usd", "max_calls", "cache_dir")

#' Which guide section explains a setting: "stage.name" (or
#' "stage.function.name" where two functions of a stage share a name) to
#' "article#section".
#' @noRd
.gr_setting_guides <- c(
  ingest.clean = "ingest#set-clean",
  ingest.cleaner_opts = "ingest#set-clean",
  "ingest.cleaner_opts.references_after" = "ingest#set-clean",
  "ingest.cleaner_opts.header_max_chars" = "ingest#set-clean",
  "ingest.cleaner_opts.header_min_repeats" = "ingest#set-clean",
  ingest.ocr = "ingest#set-ocr", ingest.ocr_lang = "ingest#set-ocr",
  ingest.ocr_dpi = "ingest#set-ocr", ingest.ocr_min_chars = "ingest#set-ocr",
  ingest.ocr_trigger = "ingest#set-ocr",
  segment.method = "segment#set-method",
  segment.max_tokens = "segment#set-max-tokens",
  segment.overlap_tokens = "segment#set-overlap",
  segment.context_source = "segment#set-contextual",
  segment.context_reply_tokens = "segment#set-contextual",
  segment.context_document_tokens = "segment#set-contextual",
  segment.proposition_batch_tokens = "segment#set-contextual",
  segment.proposition_reply_tokens = "segment#set-contextual",
  segment.semantic_threshold = "segment#set-semantic",
  segment.table_packing = "segment#set-tables",
  segment.proposition_check = "segment#set-contextual",
  segment.proposition_context_tokens = "segment#set-contextual",
  segment.packing = "segment#set-packing", segment.runt_merge = "segment#set-packing",
  segment.min_tokens = "segment#set-packing",
  read.reader = "readers#set-reader", read.skim_model = "readers#set-reader",
  read.summary_model = "readers#set-reader",
  read.top_k = "readers#set-top-k", read.min_score = "readers#set-top-k",
  read.mmr = "readers#set-mmr",
  read.lexical_blend = "readers#set-lexical", read.bm25_k1 = "readers#set-lexical",
  read.bm25_b = "readers#set-lexical", read.fusion = "readers#set-lexical",
  read.rrf_k = "readers#set-lexical",
  read.context_order = "readers#set-context-order", read.restate = "readers#set-context-order",
  read.restate_tokens = "readers#set-context-order",
  read.verify = "readers#set-verify", read.cite = "readers#set-verify",
  read.answer_format = "readers#set-answer-format",
  read.premise = "readers#set-premise", read.premise_verdict = "readers#set-premise",
  read.accept_near_verbatim = "readers#set-verify",
  read.effort = "readers#set-effort",
  read.max_merge_levels = "readers#set-merge-levels", read.fan_in = "readers#set-merge-levels",
  read.max_levels = "readers#set-merge-levels",
  read.unskip_k = "readers#set-preview", read.reread_on = "readers#set-preview",
  read.low_score = "readers#set-low-score", read.rerank_min_score = "readers#set-low-score",
  read.rerank_candidates = "readers#set-low-score",
  screen.criteria_schema = "review#set-screen-reply",
  screen.samples = "review#set-screen-reply", screen.sample_rule = "review#set-screen-reply",
  screen.gr_calibrate.recall_target = "review#set-calibration",
  screen.gr_calibrate.conf = "review#set-calibration",
  screen.gr_calibrate.max_width = "review#set-calibration",
  screen.gr_screen_sample_size.recall_target = "review#set-calibration",
  screen.gr_screen_sample_size.conf = "review#set-calibration",
  extract.resolve = "review#set-extract", extract.require_quote = "review#set-extract",
  extract.agreement_columns = "review#set-extract",
  synthesise.coherence = "review#set-synthesis",
  synthesise.coherence_rounds = "review#set-synthesis",
  synthesise.figure_bands = "review#set-synthesis",
  synthesise.prominence = "review#set-synthesis",
  synthesise.unverified = "review#set-synthesis",
  evaluate.governor = "runs#set-governor",
  options.max_cost_usd = "runs#set-limits", options.max_calls = "runs#set-limits",
  options.max_tokens_total = "runs#set-limits", options.max_output_tokens = "runs#set-limits",
  options.allowed_models = "runs#set-limits", options.allow_unpriced = "runs#set-limits")

#' The stages of gr_settings_table(), in the order a run uses them.
#' @noRd
.gr_setting_stages <- c("ingest", "segment", "read", "screen", "extract", "synthesise",
                        "evaluate", "options")

#' Every setting of every stage
#'
#' One table of every setting harnessr has, across the stages of a run:
#' ingesting a file, cutting it into chunks, reading it, screening,
#' extracting and writing a review, evaluating, and the session's options.
#' `vignette("settings")` prints it, grouped by stage.
#'
#' The table is built when it is asked for, from what declares each
#' setting, so it says what the installed code does:
#' \describe{
#'   \item{`ingest`, `segment`, `read`}{The schemas of [gr_ingest_spec()],
#'     [gr_segment_spec()] and [gr_read_spec()] (see [gr_settings()]), with
#'     their defaults, tiers and evidence. The ingest stage adds the entries
#'     of `cleaner_opts` and `layout_opts` the built-in code reads, as
#'     `cleaner_opts.references_after` and so on, and the read stage adds the
#'     arguments of [gr_read_many()].}
#'   \item{`screen`, `extract`, `synthesise`, `evaluate`}{The arguments of
#'     the functions of each stage ([gr_screen()], [gr_reference()],
#'     [gr_calibrate()], [gr_screen_sample_size()] and [gr_stop_test()];
#'     [gr_extract()]; [gr_claims()], [gr_outline()], [gr_gaps()] and
#'     [gr_synthesise()]; [hr_benchmark()], [hr_report()], [hr_judge()] and
#'     [gr_compare()]), leaving out the inputs a call works on (the
#'     documents, the client, the trace). Defaults are the functions' own,
#'     and descriptions the first sentence of each argument's help.}
#'   \item{`options`}{Every [gr_options()] option, with its default, the
#'     evidence its rule declares, and the first sentence of its entry in
#'     the help page.}
#' }
#' Descriptions come from the installed help pages; where they cannot be
#' read, `description` is `NA`.
#'
#' @param stage `NULL` for every stage, or one or more of `"ingest"`,
#'   `"segment"`, `"read"`, `"screen"`, `"extract"`, `"synthesise"`,
#'   `"evaluate"` and `"options"`.
#' @return A data frame with one row per setting and the columns `stage`,
#'   `name`, `where` (the function that takes it, as `"gr_read_spec()"`, or
#'   `"gr_options()"`), `default` (as text: a string without quotes, the
#'   first choice of a set of choices, other values as R code), `tier`
#'   (`"basic"` for the few settings most runs change, else
#'   `"advanced"`), `status` and `source` (where the default came from:
#'   `"measured"`, `"cited"` or `"untested"` and why, `NA` when nothing is
#'   declared), `description`, and `guide`, the guide section that explains
#'   how to choose it, as `"readers#set-top-k"` (the article, then the
#'   section's id), or `NA`.
#' @seealso [gr_settings()] for one spec's schema, [hr_sweep()] to test a
#'   setting, `vignette("settings")`
#' @export
#' @examples
#' s <- gr_settings_table()
#' table(s$stage)
#' s[s$tier == "basic", c("stage", "name", "default")]
#' gr_settings_table("synthesise")[, c("name", "default", "status")]
gr_settings_table <- function(stage = NULL) {
  if (!is.null(stage) && (!is.character(stage) || !length(stage) || anyNA(stage) ||
                          !all(stage %in% .gr_setting_stages))) {
    gr_abort(sprintf("`stage` must be NULL or one or more of %s.",
                     paste0("\"", .gr_setting_stages, "\"", collapse = ", ")),
             class = "gr_bad_setting")
  }
  rd <- settings_rd_db()
  rows <- c(
    list(schema_rows("ingest", "gr_ingest_spec()", .gr_ingest_schema),
         ingest_sub_rows(),
         schema_rows("segment", "gr_segment_spec()", .gr_segment_schema),
         schema_rows("read", "gr_read_spec()", .gr_read_schema)),
    lapply(names(.gr_stage_functions), function(fn) function_rows(fn, rd)),
    list(option_rows(rd)))
  out <- do.call(rbind, rows)
  out$guide <- unname(vapply(seq_len(nrow(out)), function(i) {
    fn <- sub("\\(\\)$", "", out$where[i])
    keys <- c(paste(out$stage[i], fn, out$name[i], sep = "."),
              paste(out$stage[i], out$name[i], sep = "."))
    hit <- keys[keys %in% names(.gr_setting_guides)]
    if (length(hit)) .gr_setting_guides[[hit[1]]] else NA_character_
  }, character(1)))
  out <- out[order(match(out$stage, .gr_setting_stages)), , drop = FALSE]
  if (!is.null(stage)) out <- out[out$stage %in% stage, , drop = FALSE]
  rownames(out) <- NULL
  out
}

#' Rows of the table, one per setting.
#' @noRd
settings_rows <- function(stage, where, name, default, tier, status, source, description) {
  n <- length(name)
  data.frame(stage = rep(stage, n), name = name, where = rep_len(where, n), default = default,
             tier = tier, status = status, source = source, description = description,
             stringsAsFactors = FALSE)
}

#' The rows of a spec schema.
#' @noRd
schema_rows <- function(stage, where, schema) {
  d <- as.data.frame(schema)
  settings_rows(stage, where, d$name, d$default, d$tier, d$status, d$source,
                vapply(d$help, settings_sentence, character(1), USE.NAMES = FALSE))
}

#' The rows of the entries of an ingest spec's `cleaner_opts` and
#' `layout_opts`.
#' @noRd
ingest_sub_rows <- function() {
  co <- .gr_cleaner_opts
  lo <- formals(drop_running_lines)[.gr_layout_opt_names]
  rbind(
    settings_rows("ingest", "gr_ingest_spec()", paste0("cleaner_opts.", names(co)),
                  vapply(co, function(o) format_setting_value(o$default), ""),
                  "advanced", vapply(co, function(o) o$evidence$status, ""),
                  vapply(co, function(o) o$evidence$source, ""),
                  vapply(co, function(o) o$help, "")),
    settings_rows("ingest", "gr_ingest_spec()", paste0("layout_opts.", names(lo)),
                  vapply(lo, function(v) format_setting_value(eval(v)), ""), "advanced",
                  "untested", "Set when the PDF reader was written; not tuned.",
                  unname(.gr_layout_opt_help[names(lo)])))
}

#' The rows of one stage function's arguments, inputs left out.
#' @noRd
function_rows <- function(fn, rd) {
  decl <- .gr_stage_functions[[fn]]
  fun <- get(fn, envir = asNamespace("harnessr"))
  f <- formals(fun)
  args <- setdiff(names(f), c(decl$inputs, "..."))
  key <- paste(fn, args, sep = ".")
  ev <- lapply(key, function(k) .gr_stage_evidence[[k]])
  desc <- rd_argument_text(rd, fn)
  settings_rows(decl$stage, paste0(fn, "()"), args,
                vapply(args, function(a) {
                  # A vector of strings is a set of choices when the function
                  # picks one with match.arg(), or passes it on to one that
                  # does; not when its help calls it a vector.
                  show_formal(f[[a]], uses_match_arg(fun, a) ||
                                !grepl("vector", as_chr1(desc[a], ""), fixed = TRUE))
                }, character(1), USE.NAMES = FALSE),
                ifelse(key %in% .gr_stage_basic, "basic", "advanced"),
                vapply(ev, function(e) as_chr1(e$status, NA_character_), ""),
                vapply(ev, function(e) as_chr1(e$source, NA_character_), ""),
                unname(vapply(args, function(a) settings_sentence(desc[a]), character(1))))
}

#' The rows of the options.
#' @noRd
option_rows <- function(rd) {
  nms <- names(gr_defaults)
  desc <- rd_option_text(rd)
  ev <- lapply(nms, function(nm) .gr_option_rules[[nm]]$evidence)
  settings_rows("options", "gr_options()", nms,
                vapply(gr_defaults, function(v) {
                  if (is.character(v) && length(v) == 1L) v else format_setting_value(v)
                }, character(1), USE.NAMES = FALSE),
                ifelse(nms %in% .gr_option_basic, "basic", "advanced"),
                vapply(ev, function(e) as_chr1(e$status, NA_character_), ""),
                vapply(ev, function(e) as_chr1(e$source, NA_character_), ""),
                unname(vapply(nms, function(a) settings_sentence(desc[a]), character(1))))
}

#' A function argument's default as text: a string without quotes, a single
#' number or logical as its value, the first of a vector of string choices
#' the function picks from with match.arg(), anything else as R code, and ""
#' for an argument with no default.
#' @noRd
show_formal <- function(f, choices = FALSE) {
  if (is.symbol(f) && !nzchar(as.character(f))) return("")
  if (is.character(f) && length(f) == 1L) return(f)
  if (is.atomic(f) && length(f) == 1L) return(format_setting_value(f))
  if (choices && is.call(f) && identical(f[[1]], as.name("c")) && length(f) > 2L &&
      is.null(names(f)) && all(vapply(as.list(f)[-1], is.character, logical(1)))) {
    return(f[[2]])
  }
  paste(deparse(f, width.cutoff = 500L), collapse = "")
}

#' Whether a function chooses one of an argument's values with match.arg(),
#' so its default is the first of them.
#' @noRd
uses_match_arg <- function(fn, arg) {
  code <- paste(deparse(body(fn)), collapse = " ")
  grepl(sprintf("match.arg\\(\\s*%s\\s*[,)]", arg), code)
}

#' The package's help pages as parsed Rd, from the installed help or, when
#' the package is loaded from its source tree, from man/. An empty list when
#' neither can be read.
#' @noRd
settings_rd_db <- function() {
  root <- tryCatch(getNamespaceInfo(asNamespace("harnessr"), "path"),
                   error = function(e) "")
  tryCatch({
    if (dir.exists(file.path(root, "help"))) tools::Rd_db("harnessr")
    else if (dir.exists(file.path(root, "man"))) tools::Rd_db(dir = root)
    else list()
  }, error = function(e) list())
}

#' The help page that documents a topic, or NULL.
#' @noRd
rd_page <- function(rd, topic) {
  for (page in rd) {
    tags <- vapply(page, function(s) as_chr1(attr(s, "Rd_tag"), ""), character(1))
    al <- vapply(page[tags %in% c("\\alias", "\\name")], rd_text, character(1))
    if (topic %in% trimws(al)) return(page)
  }
  NULL
}

#' The text of an Rd fragment, markup dropped, white space squeezed.
#' @noRd
rd_text <- function(x) {
  tag <- as_chr1(attr(x, "Rd_tag"), "")
  if (identical(tag, "COMMENT")) return("")
  if (identical(tag, "\\dots") || identical(tag, "\\ldots")) return("...")
  if (is.character(x)) return(paste(x, collapse = ""))
  paste(vapply(x, rd_text, character(1)), collapse = "")
}

#' An argument's help text, by argument name, for a function. An argument
#' documented as "As [other()]" takes the other function's text, followed
#' up to three pages deep.
#' @noRd
rd_argument_text <- function(rd, fn, depth = 0L) {
  page <- rd_page(rd, fn)
  out <- character(0)
  if (is.null(page)) return(out)
  for (sec in page) {
    if (!identical(attr(sec, "Rd_tag"), "\\arguments")) next
    for (it in sec) {
      if (!identical(attr(it, "Rd_tag"), "\\item") || length(it) < 2L) next
      nms <- trimws(strsplit(rd_text(it[[1]]), ",", fixed = TRUE)[[1]])
      txt <- squish_text(rd_text(it[[2]]))
      out[nms] <- txt
    }
  }
  if (depth < 3L) {
    for (a in names(out)) {
      m <- regmatches(out[[a]], regexec("^As ([a-z_]+)\\(\\)", out[[a]]))[[1]]
      if (length(m) == 2L && !identical(m[2], fn)) {
        other <- rd_argument_text(rd, m[2], depth = depth + 1L)
        if (a %in% names(other)) out[[a]] <- other[[a]]
      }
    }
  }
  out
}

#' Each option's entry in the Options section of gr_options()'s help, by
#' option name.
#' @noRd
rd_option_text <- function(rd) {
  page <- rd_page(rd, "gr_options")
  out <- character(0)
  if (is.null(page)) return(out)
  for (sec in page) {
    if (!identical(attr(sec, "Rd_tag"), "\\section") ||
        !identical(trimws(rd_text(sec[[1]])), "Options")) next
    walk <- function(x) {
      if (identical(attr(x, "Rd_tag"), "\\item") && length(x) >= 2L) {
        head <- rd_text(x[[1]])
        nms <- regmatches(head, gregexpr("[a-z_]+(?= \\()", head, perl = TRUE))[[1]]
        out[nms] <<- squish_text(rd_text(x[[2]]))
      } else if (is.list(x)) {
        for (y in x) walk(y)
      }
    }
    walk(sec[[2]])
  }
  out
}

#' White space squeezed to single spaces.
#' @noRd
squish_text <- function(x) trimws(gsub("\\s+", " ", x))

#' The first sentence of a text, or NA.
#' @noRd
settings_sentence <- function(x) {
  x <- as_chr1(x, NA_character_)
  if (is.na(x) || !nzchar(x)) return(NA_character_)
  x <- squish_text(x)
  ends <- gregexpr("[.!?](?=\\s|$)", x, perl = TRUE)[[1]]
  for (e in ends[ends > 0]) {
    before <- substr(x, 1L, e)
    # An abbreviation does not end a sentence.
    if (grepl("(^|[^A-Za-z])(e\\.g|i\\.e|etc|vs|cf)\\.$", before)) next
    return(before)
  }
  x
}
