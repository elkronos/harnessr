# doc-ingest-run.R -- AXIS 1: the public ingestion entry point.
#
# WHY THIS FILE EXISTS
# `parse_text()` cached its result under `normalizePath(file_path)` and nothing
# else. Not the chunk method, not the token limit, not the cleaning flags, not
# the file's own mtime or content hash. So:
#
#     a <- parse_text(f, chunk_method = "naive",    chunk_token_limit = 3000)
#     b <- parse_text(f, chunk_method = "semantic", chunk_token_limit = 5)
#     identical(a, b)   # TRUE -- every argument of `b` was silently discarded
#
# and editing the file on disk did not invalidate anything. In a Shiny process
# the cache lived in `.GlobalEnv`, shared across every user session, with no way
# to clear it. That single defect made the repository's stated goal -- fine
# control over how information is broken up -- unreachable: whichever settings
# ran first won for the rest of the session.
#
# The cache key here covers the file identity (path + size + mtime) AND every
# option that can change the output. Ingestion also now stops at clean text:
# segmentation is a separate axis with its own cache, so re-chunking a document
# a dozen different ways costs one extraction, not twelve.

#' Describe an ingestion configuration
#'
#' @param clean A preset name (`"none"`, `"minimal"`, `"standard"`,
#'   `"academic"`, `"scan"`, `"legacy"`) or a character vector of cleaner
#'   names from `gr_cleaners()`.
#' @param ocr `"auto"` (OCR pages with no text layer), `"always"`, or `"never"`.
#' @param ocr_lang Tesseract language code.
#' @param ocr_dpi Render density for PDF OCR.
#' @param ocr_min_chars A page with fewer characters than this is treated as
#'   needing OCR under `ocr = "auto"`. Zero or more; `Inf` marks every page.
#'   Anything else warns and uses 40.
#' @param min_chars Refuse the document if less than this much text survives.
#' @param extractor Force a specific extractor name instead of dispatching on
#'   the file extension.
#' @param parallel Parallelise page-level OCR.
#' @param cleaner_opts Extra options passed to individual cleaners, as a named
#'   list. The built-in cleaners read these:
#'   \describe{
#'     \item{`references_after` (0.4)}{For the `references` cleaner (in the
#'       `academic` and `legacy` presets): a References, Bibliography or Works
#'       cited heading, on a line of its own and optionally numbered or a
#'       Markdown heading such as `## References`, ends the text only when it
#'       starts at or after this
#'       share of the text, so an entry in a table of contents does not cut
#'       the document. A number in \[0, 1\]; a value that cannot be read
#'       warns and uses 0.4. Untested: set when the cleaner was written.}
#'     \item{`header_max_chars` (80)}{For the `headers_footers` cleaner (in
#'       the `scan` preset): the longest line, in characters, that can be
#'       taken for a running head or foot. Untested.}
#'     \item{`header_min_repeats` (3)}{For `headers_footers`: how many times a
#'       line must recur to be taken for one. Values below 3 are read as 3,
#'       and a text of fewer than 8 lines is left alone. Untested.}
#'   }
#' @param layout How a PDF page's text is put in reading order. `"auto"` drops
#'   running heads and feet (short lines repeated at the top or bottom of many
#'   pages), reads a page set in two columns one column after the other, and
#'   marks headings, taken from the PDF's bookmarks or recognised as a standard
#'   section name ("Introduction", "Methods" and so on), so blocks carry
#'   sections. `"raw"` keeps each page as pdftools lays it out. Other formats
#'   are not affected. Stored in the spec only when it is not `"auto"`, so a
#'   default spec keeps the cache and store keys it had before the setting
#'   existed.
#' @param layout_opts Under `layout = "auto"`, a named list that changes how
#'   running heads and feet are found on PDF pages: `depth` (2, lines at each
#'   edge of a page that are candidates), `share` (0.4, the share of pages a
#'   line must recur on), `min_pages` (3, the fewest pages a document needs
#'   before any line is dropped, and the fewest a line must recur on),
#'   `max_chars` (200, the longest candidate line) and `max_words` (5, above
#'   which a numbered line must carry its number where a page number is set).
#'   Names left out keep these defaults, which were set when the PDF reader
#'   was written and are untested. An unknown name is an error. Stored in the
#'   spec only when it is not empty.
#' @return A list of class `gr_ingest_spec`.
#'
#' @section Where the defaults come from:
#' Each setting's default, its tier and the evidence behind the value, as in
#' [gr_read_spec()].
#'
#' `r schema_sources_md(.gr_ingest_schema)`
#' @export
#' @seealso [gr_ingest()], [gr_cleaners()] for the individual step names,
#'   [gr_clean()] to preview a configuration on your own text
#' @family ingest functions
#' @examples
#' # What each preset costs you, on a real document, before any model call.
#' vapply(c("none", "minimal", "standard", "academic", "scan"),
#'        function(p) gr_ingest(gr_example(), gr_ingest_spec(clean = p))$stats$chars,
#'        integer(1))
#'
#' # Or name the steps yourself; see gr_cleaners() for what is available.
#' gr_ingest_spec(clean = c("page_numbers", "references"), ocr = "never")$clean
#'
#' # A bibliography heading counts only in the last half of the text.
#' gr_ingest_spec(clean = "academic", cleaner_opts = list(references_after = 0.5))
gr_ingest_spec <- function(clean = "standard", ocr = c("auto", "always", "never"),
                           ocr_lang = "eng", ocr_dpi = 300, ocr_min_chars = 40L,
                           min_chars = 20L, extractor = NULL, parallel = NULL,
                           cleaner_opts = list(), layout = c("auto", "raw"),
                           layout_opts = list()) {
  p <- hr_validate(.gr_ingest_schema, mget(names(.gr_ingest_schema), environment()))
  spec <- structure(list(clean = p$clean, ocr = p$ocr, ocr_lang = p$ocr_lang,
                         ocr_dpi = p$ocr_dpi, ocr_min_chars = p$ocr_min_chars,
                         min_chars = p$min_chars, extractor = p$extractor,
                         parallel = p$parallel, cleaner_opts = p$cleaner_opts),
                    class = "gr_ingest_spec")
  if (!identical(p$layout, "auto")) spec$layout <- p$layout
  # Only when set, as `layout`: the spec is hashed into the document cache and
  # store keys.
  if (length(p$layout_opts)) spec$layout_opts <- p$layout_opts
  spec
}

#' The entries of an ingest spec's `layout_opts` and `cleaner_opts`, flattened
#' as `layout_opts.depth` and `cleaner_opts.references_after`, for the
#' settings column of gr_compare(). Both lists are empty by default, so every
#' entry is a change from it. The spec's other fields are left out: a recipe
#' names its cleaning preset already, and the column never listed them.
#' @noRd
ingest_settings <- function(spec) {
  flat <- function(nm) {
    x <- spec[[nm]]
    if (!length(x) || is.null(names(x))) return(list())
    stats::setNames(as.list(x), paste0(nm, ".", names(x)))
  }
  c(flat("layout_opts"), flat("cleaner_opts"))
}

#' The ingest step's trace detail, with the spec's `layout_opts` and
#' `cleaner_opts` entries as `settings` when it has any, so a trace says which
#' ingest settings a run used. A spec at its defaults adds nothing, and its
#' trace is as before.
#' @noRd
ingest_note <- function(detail, spec) {
  s <- tryCatch(ingest_settings(spec), error = function(e) list())
  if (length(s)) detail$settings <- s
  detail
}

#' The settings of drop_running_lines() a spec's `layout_opts` may change.
#' @noRd
.gr_layout_opt_names <- c("depth", "share", "min_pages", "max_chars", "max_words")

#' Check `layout_opts`: a named list of single numbers, each a setting of
#' drop_running_lines(), in range.
#' @noRd
check_layout_opts <- function(x, p, params) {
  if (is.null(x) || !length(x)) return(list())
  x <- as.list(x)
  nm <- names(x)
  if (is.null(nm) || any(is.na(nm) | !nzchar(nm))) {
    gr_abort("`layout_opts` must be a named list.", class = "gr_bad_setting")
  }
  bad <- setdiff(nm, .gr_layout_opt_names)
  if (length(bad)) {
    gr_abort(sprintf("`layout_opts` has unknown name(s) %s. Known: %s.",
                     paste0("'", bad, "'", collapse = ", "),
                     paste(.gr_layout_opt_names, collapse = ", ")), class = "gr_bad_setting")
  }
  rng <- list(depth = c(1, 20), share = c(0, 1), min_pages = c(2, 1e4),
              max_chars = c(10, 1e4), max_words = c(1, 100))
  for (k in nm) {
    v <- na_default(x[[k]], formals(drop_running_lines)[[k]], paste0("layout_opts$", k))
    x[[k]] <- clamp_warn(v, rng[[k]][1], rng[[k]][2], paste0("layout_opts$", k),
                         integer = !identical(k, "share"))
  }
  x
}

#' The schema of gr_ingest_spec(). Most settings are stored as given, as they
#' always were; the extractors and cleaners that read them check them.
#' @noRd
.gr_ingest_schema <- hr_schema(
  hr_param("ocr", "enum", choices = c("auto", "always", "never"), cost_class = "local",
           help = "When to OCR a page: with no text layer, always, or never.",
           evidence = ev_untested("OCR only where a page has no text layer; not compared.")),
  hr_param("layout", "enum", choices = c("auto", "raw"),
           help = "How a PDF page's text is put in reading order.", tier = "advanced",
           evidence = ev_untested(paste0("The layout pass is on; checked on the PDFs in the ",
                                         "tests, with no measured comparison against \"raw\"."))),
  hr_param("clean", "string_vector", default = "standard",
           help = "A cleaning preset, or cleaner names.", resolve = param_as_given,
           evidence = ev_untested("The preset meant for born-digital text; not compared.")),
  hr_param("ocr_lang", "string", default = "eng", tier = "advanced",
           help = "Tesseract language code.", resolve = param_as_given,
           evidence = ev_untested("English, the language of the package's own examples.")),
  hr_param("ocr_dpi", "number", default = 300, tier = "advanced", cost_class = "local",
           help = "Render density for PDF OCR.", resolve = param_as_given,
           evidence = ev_cited(paste0("Tesseract's documentation on improving output quality ",
                                      "recommends images of at least 300 DPI; not measured ",
                                      "here."))),
  # Not bare as.integer(): NA and 3e9 both became NA_integer_, and
  # `sum(nchar(text)) < NA` then failed EVERY document with "missing value
  # where TRUE/FALSE needed". The OCR threshold is read by ocr_threshold(),
  # which gr_inventory() uses too, so the survey predicts what ingestion then
  # does.
  hr_param("ocr_min_chars", "number", default = 40L, tier = "advanced",
           help = "A page with fewer characters is OCRed under ocr = 'auto'.",
           evidence = ev_untested("Set when OCR was added; not tuned."),
           resolve = function(x, p, params) ocr_threshold(x)),
  hr_param("min_chars", "integer", default = 20L,
           help = "Refuse the document if less text than this survives.",
           evidence = ev_untested("A floor that catches an empty extraction; not tuned.")),
  hr_param("extractor", "module_ref", default = NULL, kind = "extractor", tier = "advanced",
           help = "Force an extractor instead of choosing by file type.",
           evidence = ev_untested("Not a tuned value: NULL chooses by file type."),
           resolve = param_as_given),
  hr_param("parallel", "boolean", default = NULL, affects_output = FALSE, tier = "advanced",
           help = "Parallelise page-level OCR.", resolve = param_as_given,
           evidence = ev_untested(paste0("Not a tuned value: NULL follows ",
                                         "gr_options(\"parallel\"). It does not change output."))),
  hr_param("cleaner_opts", "named_map", default = list(), tier = "advanced",
           help = "Extra options passed to individual cleaners.", resolve = param_as_given,
           evidence = ev_untested(paste0("Empty: each cleaner uses its own defaults, listed ",
                                         "under `cleaner_opts`."))),
  hr_param("layout_opts", "named_map", default = list(), tier = "advanced",
           depends_on = "layout = \"auto\"",
           help = "Settings of the PDF running-head pass under layout = 'auto'.",
           evidence = ev_untested(paste0("Empty: the pass uses the values it was written with, ",
                                         "listed under `layout_opts`; none was tuned.")),
           resolve = check_layout_opts)
)

#' Ingest a document into cleaned, provenance-bearing text blocks
#'
#' The first axis. Extraction happens once and is cached, so one file read can
#' feed any number of segmentations: comparing chunking strategies costs one
#' extraction, not one per strategy. Page and section provenance survives
#' cleaning, which is what lets `ans$evidence` point back at where an answer
#' came from.
#'
#' @param source A file path, a web address, or a character vector / single
#'   string of raw text. An address starting `http://` or `https://` is
#'   downloaded and read with the extractor for what came back: a specific type
#'   the server declares, else the extension in the address, else the file's
#'   first bytes. The charset the server declares is used for HTML and text. A
#'   download that fails is an error (`gr_url_error`), one past 512 MB is
#'   refused (`gr_too_large`, which is also a `gr_url_error`), and one no
#'   extractor reads is refused (`gr_unsupported_format`). An address on this
#'   machine or a private network (localhost, 10.x, 172.16/12, 192.168.x,
#'   169.254.x, the IPv6 local ranges), and a host name that resolves to one,
#'   is refused (`gr_url_error`), after a redirect too, unless
#'   `options(harnessr.allow_local_urls = TRUE)`; behind a proxy that looks
#'   names up itself, a name that cannot be looked up here is not checked. The
#'   request uses the address in full, but the document's `source`, the
#'   messages and the errors show it without a user name and password and with
#'   its query replaced by a short fingerprint (`[query hidden 1a2b3c]`), since
#'   a presigned link carries its credentials there; two addresses that differ
#'   only in the query keep different fingerprints. A Word file, fetched or on
#'   disk, whose text parts would unpack to more than 512 MB is refused
#'   (`gr_too_large`). A one-line string ending in an
#'   extension some extractor claims is taken as a path, and is an error
#'   (`gr_file_not_found`) when no such file exists. Any other string is read as
#'   text; one that looks like a path (a directory separator and an extension no
#'   extractor claims) also raises a `gr_path_as_text` warning.
#' @param spec A `gr_ingest_spec`, a bare preset name, or `NULL` for defaults.
#' @param cache Use the session document cache. The cache key includes the file's
#'   size and mtime plus every ingestion option; for a web address, the address,
#'   so it is downloaded once a session. Registering a cleaner or extractor the
#'   ingestion uses again (as when fixing it) starts a new cache entry. The
#'   cache lives in memory for the session, is shared by everything running in
#'   the R process (every Shiny session of one app, say), and holds about
#'   256 MB of documents; past that the documents used least recently are
#'   dropped, and read again when next asked for.
#' @param trace Optional `gr_trace`.
#' @return A `gr_document`: a list with `blocks` (data frame), `text`, `source`,
#'   `spec` and `stats`.
#' @export
#' @seealso [gr_ingest_spec()] for the options, [gr_cleaners()] for the step
#'   names, [gr_extractors()] for the formats, [gr_document] for what comes
#'   back, [gr_segment()] for the next axis
#' @family ingest functions
#' @examples
#' doc <- gr_ingest(gr_example())
#'
#' # Provenance survives cleaning; this is what `ans$evidence` points back at.
#' head(doc$blocks[, c("block_id", "page", "section", "kind")], 4)
#'
#' # What each cleaning step actually removed, in characters.
#' vapply(doc$stats$clean_log, function(s) s$chars_removed, integer(1))
#'
#' # Cleaning is a choice, not a default. Compare before committing to it.
#' raw <- gr_ingest(gr_example(), gr_ingest_spec(clean = "none"))
#' c(standard = doc$stats$chars, none = raw$stats$chars)
gr_ingest <- function(source, spec = NULL, cache = NULL, trace = NULL) {
  spec <- as_ingest_spec(spec)
  cache <- isTRUE(cache %||% gr_options("cache_documents"))

  # A single-line string that carries a file extension is a PATH, not prose. If
  # it does not exist, say so. Falling through to the inline-text branch means a
  # mistyped filename becomes the document: the model is handed
  # "~/reports/q3_final.pdf" as its source text and answers about the filename,
  # with no warning and partial = FALSE.
  # `scalar` and `one_line` are different questions, and conflating them meant a
  # file whose NAME contains a newline was never looked for: file.exists() was
  # never consulted, the guard below could not fire either, and the path string
  # itself became the document text -- status "ok", partial FALSE, the model
  # answering about a filename. nchar(type = "bytes") because a string holding
  # invalid UTF-8 makes the default nchar() raise.
  scalar <- is.character(source) && length(source) == 1L && !is.na(source) &&
    nchar(source, type = "bytes") < 4096
  one_line <- scalar && !grepl("\n", source)
  # A web address is fetched, not read as text; see ingest-url.R. Space around
  # it is dropped, a trailing newline included.
  url <- scalar && is_url(source)
  if (url) source <- trimws(source)
  # Only treat a string as a path when its extension is one an extractor
  # actually claims. Matching any 1-6 character suffix rejected ordinary prose
  # ending in a decimal ("...revenue of 45.2") while still swallowing missing
  # paths whose extension was absent or longer, which then became the document.
  known_ext <- unique(tolower(unlist(lapply(gr_state$extractors, `[[`, "extensions"))))
  ext_of <- function(s) tolower(sub(".*\\.([A-Za-z0-9]+)$", "\\1", s))
  looks_like_path <- one_line && !url && grepl("\\.[A-Za-z0-9]+$", source) &&
    ext_of(source) %in% known_ext &&
    !grepl("[ \t]{2,}", source) && !grepl("\\.[0-9]+$", source)
  is_path <- scalar && file.exists(source)
  if (!is_path && looks_like_path) {
    gr_abort(sprintf(paste0("File not found: '%s'. If you meant to pass document text rather than ",
                            "a path, it must not end in something that looks like a file extension."),
                     source), class = "gr_file_not_found")
  }
  # Everything below is recorded on the document, so an answer drawn from it
  # carries the warnings too. That includes a cache hit, when extraction does
  # not run again and nothing would be raised a second time.
  rec <- warning_recorder()
  # The other half of the rule above. A mistyped or unsupported extension is not
  # one an extractor claims, so the string is read as text. That is correct,
  # since prose can end in a word with a dot in it, but a one-line string with a
  # directory separator in it is almost certainly a path, and the answer that
  # follows would be about the file name.
  if (!is_path && !looks_like_path && !url && one_line && grepl("[/\\\\]", source) &&
      grepl("\\.[A-Za-z][A-Za-z0-9]{0,5}$", source) && !grepl("[ \t]{2,}", source)) {
    withCallingHandlers(
      gr_warn(sprintf(paste0("'%s' is not an existing file, and '.%s' is not an extension harnessr ",
                             "reads, so the string itself is being read as the document. If it is ",
                             "a path, check it; harnessr reads %s."),
                      source, ext_of(source),
                      paste0(".", sort(known_ext), collapse = ", ")),
              class = "gr_path_as_text"),
      gr_warning = rec$record)
  }

  # The spec names its cleaners and extractor; the code that runs is whatever is
  # registered under those names now. Registering a fixed cleaner under its old
  # name is the ordinary way to repair one, and with names alone in the key the
  # document the broken one produced kept coming back from the cache.
  code <- ingest_code(spec, is_path = is_path, url = url, source = source)
  if (is_path) {
    fi <- file.info(source)
    key <- gr_hash(list(normalizePath(source, winslash = "/", mustWork = FALSE),
                        fi$size, as.numeric(fi$mtime), unclass(spec), code))
  } else if (url) {
    # The address, not what it serves today: a page that changes during a
    # session is read as it was the first time, as a file is until it is saved.
    key <- gr_hash(list("url", source, unclass(spec), code))
  } else {
    # Hash the SAME string the pipeline goes on to ingest. Joining with "\n"
    # here while ingestion joined with "\n\n" made a two-element vector hash
    # identically to a one-element string containing a single newline, and the
    # wrong cached document came back.
    key <- gr_hash(list("inline",
                        paste(vapply(source, as_chr1, character(1), USE.NAMES = FALSE),
                              collapse = "\n\n"),
                        unclass(spec), code))
  }

  if (cache && !is.null(doc <- doc_cache_get(key))) {
    gr_msg("Using cached ingestion for this document + settings.")
    trace_note(trace, "ingest", ingest_note(list(cached = TRUE, blocks = nrow(doc$blocks)), spec))
    return(doc)
  }

  if (is_path || url) {
    path <- source
    # A web address is kept and shown as url_shown() shows it, without the
    # credentials a presigned link carries in its query; the request and the
    # cache key above use it in full. `label` is what messages and the trace
    # call the document: a file by its name, an address in full, since its host
    # is half of what names it (and basename() warns past PATH_MAX, which a
    # presigned address can pass).
    src <- if (url) url_shown(source) else normalizePath(source, winslash = "/", mustWork = FALSE)
    label <- if (url) src else basename(src)
    if (url) {
      gr_msg(sprintf("Fetching '%s'.", label))
      path <- fetch_url(source)
      on.exit(unlink(path), add = TRUE)
    }
    ext <- tolower(tools::file_ext(path))
    ex <- if (!is.null(spec$extractor)) registry_get("extractors", spec$extractor, state = gr_state)
          else extractor_for(ext)
    if (is.null(ex)) {
      gr_abort(sprintf("No extractor for '.%s'. Registered extensions: %s. Add one with gr_register_extractor().",
                       ext, paste(sort(unique(unlist(lapply(gr_state$extractors, `[[`, "extensions")))),
                                  collapse = ", ")),
               class = "gr_unsupported_format")
    }
    gr_msg(sprintf("Extracting '%s' with the '%s' extractor.",
                   if (url) label else basename(source), ex$name))
    raw <- withCallingHandlers(ex$fn(path, spec), gr_warning = rec$record)
    unread <- attr(raw, "gr_unread_pages", exact = TRUE)
    # How many pages the file has, when the extractor says (extract_pdf does).
    # Read before as_blocks(), which keeps no attributes. Anything but one
    # finite number of at least one is ignored, as if nobody had said.
    npages <- attr(raw, "gr_pages", exact = TRUE)
    npages <- if (is.numeric(npages) && length(npages) == 1L) as_int1(npages, NA_integer_)
              else NA_integer_
    if (!is.na(npages) && npages < 1L) npages <- NA_integer_
    blocks <- as_blocks(raw)
    blocks$text <- to_utf8(blocks$text)
  } else {
    txt <- paste(vapply(source, as_chr1, character(1), USE.NAMES = FALSE), collapse = "\n\n")
    txt <- to_utf8(txt)
    blocks <- as_blocks(data.frame(text = paragraphs_of(txt), stringsAsFactors = FALSE))
    unread <- NULL
    npages <- NA_integer_
    src <- "<inline text>"
    label <- src
  }
  unread <- sort(unique(as.integer(unread[!is.na(unread)])))

  raw_chars <- sum(nchar(blocks$text))
  steps <- resolve_clean_steps(spec$clean)
  # The blocks' pages go with them, so a step that decides by where a line
  # stands on its page (headers_footers) can see the pages.
  clean_opts <- utils::modifyList(as.list(spec), spec$cleaner_opts %||% list())
  clean_opts[[".pages"]] <- blocks$page
  cleaned <- withCallingHandlers(
    gr_clean(blocks$text, steps = steps, opts = clean_opts),
    gr_warning = rec$record)
  clean_log <- attr(cleaned, "gr_clean_log")
  blocks$text <- mark_utf8(as.character(cleaned))
  blocks <- blocks[has_content(blocks$text), , drop = FALSE]
  rownames(blocks) <- NULL

  if (!nrow(blocks) || sum(nchar(blocks$text)) < spec$min_chars) {
    gr_abort(sprintf(paste0("Only %d characters survived ingestion of '%s' (minimum %d). ",
                            "The file may be empty, image-only with OCR disabled, or your ",
                            "cleaning steps may be too aggressive: %d characters were removed ",
                            "by cleaners: %s."),
                     sum(nchar(blocks$text)), label, spec$min_chars,
                     raw_chars - sum(nchar(blocks$text)),
                     paste(vapply(clean_log, function(l) sprintf("%s(-%d)", l$step, l$chars_removed),
                                  character(1)), collapse = " ")),
             class = "gr_empty_document")
  }

  blocks$block_id <- seq_len(nrow(blocks))
  doc <- structure(list(
    blocks = blocks,
    text = mark_utf8(paste(blocks$text, collapse = "\n\n")),
    source = src,
    spec = spec,
    stats = list(blocks = nrow(blocks), chars = sum(nchar(blocks$text)),
                 chars_removed = raw_chars - sum(nchar(blocks$text)),
                 tokens = sum(gr_count_tokens(blocks$text)),
                 # A trailing page that never became text is still a page of the
                 # document; counting only pages with blocks under-reported it.
                 # So is one whose blocks the cleaner took out (a references
                 # page, a page of furniture), which only the extractor's own
                 # count of pages knows about.
                 pages = if (all(is.na(c(blocks$page, unread, npages)))) NA_integer_
                         else as.integer(max(c(blocks$page, unread, npages), na.rm = TRUE)),
                 clean_steps = steps, clean_log = clean_log,
                 unread_pages = unread),
    warnings = rec$get()
  ), class = "gr_document")

  if (cache) doc_cache_put(key, doc)
  trace_note(trace, "ingest", ingest_note(list(cached = FALSE, source = label,
                                               blocks = nrow(blocks), tokens = doc$stats$tokens,
                                               clean_steps = steps), spec))
  gr_msg(sprintf("Ingested %d block(s), ~%d tokens (%d chars removed by cleaning).",
                 doc$stats$blocks, doc$stats$tokens, doc$stats$chars_removed))
  doc
}

#' @noRd
as_ingest_spec <- function(spec) {
  if (inherits(spec, "gr_ingest_spec")) return(spec)
  if (is.null(spec)) return(gr_ingest_spec())
  if (is.character(spec) && length(spec) == 1L) return(gr_ingest_spec(clean = spec))
  if (is.list(spec)) return(do.call(gr_ingest_spec, spec))
  gr_abort("`ingest` must be a gr_ingest_spec, a preset name, or a named list.")
}

#' The registered code an ingestion with `spec` would run, for its cache key.
#'
#' The cleaners the spec's steps name, with the stage and scope that decide
#' their order and reach, and the extractor. A file is read by the extractor the
#' spec forces or its extension selects. What a web address serves decides its
#' extractor and is not known before the download, so every registered one goes
#' in. Inline text uses none. Nothing here raises: a name that is not
#' registered is reported where it is used, as before.
#'
#' Each entry goes in with its code and with when it was registered. The code
#' alone cannot see what the function calls: a cleaner that calls a global
#' helper, or reads a global pattern, is the same code after the helper is
#' fixed, so registering it again still served the document the broken helper
#' had left. Registering an entry again is how a fix is put in place, so it
#' starts a new cache entry for every document that uses it. The document cache
#' lives only as long as the session, so a key that differs between sessions
#' costs nothing.
#' @noRd
ingest_code <- function(spec, is_path, url, source) {
  steps <- tryCatch(resolve_clean_steps(spec$clean), error = function(e) character(0))
  cleaners <- lapply(steps, function(s) {
    e <- gr_state$cleaners[[s]]
    if (is.null(e)) NULL else list(e$fn, e$stage, e$scope %||% "block", e$registered)
  })
  forced <- spec$extractor
  code_of <- function(e) if (is.null(e)) NULL else list(e$fn, e$registered)
  ex <- if (!is.null(forced)) {
    tryCatch(code_of(gr_state$extractors[[as_chr1(forced)]]), error = function(e) NULL)
  } else if (url) {
    lapply(gr_state$extractors, function(e) list(e$fn, e$extensions, e$registered))
  } else if (is_path) {
    code_of(extractor_for(tolower(tools::file_ext(source))))
  }
  list(cleaners = cleaners, extractor = ex)
}

#' A number no earlier registration of a cleaner or extractor has had.
#'
#' Stored on the entry, it tells the ingest cache that the entry was put in
#' place again; see ingest_code().
#' @noRd
registration_stamp <- function() {
  gr_state$registrations <- (gr_state$registrations %||% 0) + 1
  gr_state$registrations
}

#' @export
print.gr_document <- function(x, ...) {
  cat(sprintf("<gr_document> %s\n", x$source))
  cat(sprintf("  %d blocks, ~%d tokens, %d chars (%d removed by cleaning)\n",
              x$stats$blocks, x$stats$tokens, x$stats$chars, x$stats$chars_removed))
  if (!is.na(x$stats$pages)) cat(sprintf("  %d page(s)\n", x$stats$pages))
  cat(sprintf("  cleaners: %s\n", paste(x$stats$clean_steps, collapse = ", ") %|z|% "none"))
  unread <- x$stats$unread_pages %||% integer(0)
  if (length(unread)) {
    cat(sprintf("  pages that never became text: %s\n",
                paste(utils::head(unread, 20), collapse = ", ")))
  }
  w <- x[["warnings", exact = TRUE]] %||% character(0)
  if (length(w)) cat(sprintf("  %d warning(s), in $warnings\n", length(w)))
  cat(sprintf("  first block: %s\n", substr(x$blocks$text[1], 1, 120)))
  invisible(x)
}

#' @export
as_json.gr_document <- function(x, pretty = TRUE, ...) {
  # Arrays whatever their length: unboxed, one cleaning step or one unread page
  # was written as a string or a number where other documents have a list.
  as_json.default(list(source = x$source,
                       stats = json_arrays(x$stats, c("clean_steps", "unread_pages")),
                       blocks = x$blocks), pretty = pretty, ...)
}

#' The OCR threshold, read one way everywhere it is read.
#'
#' `gr_inventory()` predicts what ingestion will do, so the two must agree on
#' what a threshold means: a number of characters, zero or more, where `Inf`
#' marks every page for OCR. Anything else warns and takes the default. An
#' integer while it fits one, so the default leaves cache keys as they were.
#' @noRd
ocr_threshold <- function(x, default = 40L) {
  n <- suppressWarnings(as.numeric(x))
  if (length(n) != 1L || is.na(n) || n < 0) {
    gr_warn(sprintf(paste0("`ocr_min_chars` must be a number of characters, zero or more; ",
                           "using the default (%s)."), format(default)),
            class = "gr_bad_setting")
    return(default)
  }
  if (is.finite(n) && n <= .Machine$integer.max) as.integer(n) else n
}
