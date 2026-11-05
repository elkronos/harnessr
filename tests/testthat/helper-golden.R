# helper-golden.R -- the machinery behind test-golden.R and dev/record-golden.R.
#
# Both of them need to compute the same record of what the package does, one
# to compare it with the fixtures and one to write them, so it lives here,
# where testthat loads it and the recorder can source it. Nothing in this file
# runs on load: it only defines functions.
#
# What a "golden run" records, for one recipe, reader or corpus stage run on
# the bundled example with a fixed mock:
#
#   calls   every request the run sent, in order: its label, model and
#           parameters, the roles and sizes of its messages, a hash of the
#           whole request (messages, parameters and schema) and the response
#           cache key the package itself computed for it.
#   trace   the run's trace as as_json() writes it, with what changes from one
#           run to the next taken out (times, durations, run ids, the package
#           version) and each prompt and reply reduced to a hash.
#   result  a hash of what the run handed back.
#
# The mock's client id is pinned, and the document and embedding caches are
# flushed before every run, so a run depends on nothing but its inputs.

# The fixture directory, from the test directory or from the repository root.
golden_dir <- function(root = NULL) {
  if (!is.null(root)) return(file.path(root, "tests", "testthat", "fixtures", "golden"))
  testthat::test_path("fixtures", "golden")
}

# The packages a golden run needs. Both are imports of harnessr, so they are
# normally present; digest matters twice over, since without it the package
# keys its cache with a fallback hash and every recorded key would differ. The
# test skips, naming the package, when one is missing; it never passes without
# comparing.
golden_needs <- c("digest", "jsonlite")

golden_question <- "What was revenue in 2024?"

# ---------------------------------------------------------------------------
# Canonical serialisation and hashing.
# ---------------------------------------------------------------------------

# Names sorted at every depth, so a field's position in a list never changes a
# hash or a fixture. An unnamed list keeps its order: its order is data.
golden_sort <- function(x) {
  if (is.list(x)) {
    nm <- names(x)
    x <- lapply(unclass(x), golden_sort)
    if (!is.null(nm)) {
      o <- order(nm, method = "radix")
      x <- x[o]
      names(x) <- nm[o]
    }
    return(x)
  }
  if (is.character(x)) {
    asis <- inherits(x, "AsIs")
    x <- enc2utf8(x)
    if (asis) x <- I(x)
  }
  if (!is.null(names(x)) && is.atomic(x)) {
    # A named vector's order is data (an outline's sections), and jsonlite
    # would drop its names, so the two are kept side by side.
    return(list(names = enc2utf8(names(x)), values = unname(x)))
  }
  x
}

golden_json <- function(x, pretty = FALSE) {
  out <- jsonlite::toJSON(golden_sort(x), auto_unbox = TRUE, digits = NA, null = "null",
                          na = "null", pretty = pretty, force = TRUE)
  enc2utf8(as.character(out))
}

# The first 16 hex digits of a SHA-256 over the canonical JSON's UTF-8 bytes.
golden_hash <- function(x) {
  s <- if (is.character(x) && length(x) == 1L && is.null(names(x))) enc2utf8(x) else golden_json(x)
  substr(digest::digest(charToRaw(s), algo = "sha256", serialize = FALSE), 1L, 16L)
}

# ---------------------------------------------------------------------------
# Taking out what is specific to a machine or a moment.
# ---------------------------------------------------------------------------

# Fields that change between two runs of the same inputs, dropped wherever they
# appear: a step's clock time and duration, the trace's start, run id and
# elapsed time, and the package version its meta records (which would make
# every release a fixture change).
golden_volatile <- c("at", "seconds", "started", "run_id", "elapsed_s", "readgpt")

# Every absolute path a run can mention, longest first, with what it becomes.
golden_paths <- function() {
  ex <- harnessr::readgpt_example()
  p <- c(normalizePath(ex, winslash = "/", mustWork = FALSE), ex,
         normalizePath(dirname(ex), winslash = "/", mustWork = FALSE), dirname(ex),
         normalizePath(tempdir(), winslash = "/", mustWork = FALSE), tempdir())
  to <- c("<example>", "<example>", "<extdata>", "<extdata>", "<tempdir>", "<tempdir>")
  keep <- !duplicated(p) & nzchar(p)
  p <- p[keep]; to <- to[keep]
  o <- order(-nchar(p))
  list(from = p[o], to = to[o])
}

golden_scrub <- function(x, paths = golden_paths()) {
  if (is.list(x)) {
    if (!is.null(names(x))) x <- x[!names(x) %in% golden_volatile]
    return(lapply(x, golden_scrub, paths = paths))
  }
  if (is.character(x)) {
    for (i in seq_along(paths$from)) x <- gsub(paths$from[i], paths$to[i], x, fixed = TRUE)
    # A temporary file named by the session (file1a2b3c.txt) is not stable
    # whichever directory it is in.
    x <- gsub("file[0-9a-f]{6,}", "<tempfile>", x)
  }
  x
}

# ---------------------------------------------------------------------------
# The mock and the cache keys.
# ---------------------------------------------------------------------------

# One fixed reply for every kind of request the readers and the review stages
# send, chosen from the system prompt. Every reply is a pure function of the
# request, so the run is the same however often it is made.
golden_reply <- function(messages, params) {
  sys <- as.character(messages[[1]]$content)
  all <- paste(vapply(messages, function(m) as.character(m$content), character(1)),
               collapse = "\n")
  has <- function(s, where = sys) grepl(s, where, fixed = TRUE)
  line <- "Northwind Instruments reported revenue of 45.2 million dollars in fiscal 2024"

  if (has("Rate how useful")) return('{"score": 8, "reason": "relevant"}')
  if (has("reading iteratively")) {
    return('{"can_answer": true, "answer": "Revenue was 45.2 million dollars.", "next_query": ""}')
  }
  if (has("You plan how to read a document")) {
    last <- as.character(messages[[length(messages)]]$content)
    n <- suppressWarnings(as.integer(sub(".*each of the ([0-9]+) sections.*", "\\1", last)))
    n <- if (is.na(n)) 1L else max(1L, n)
    return(as.character(jsonlite::toJSON(list(sections = data.frame(
      id = seq_len(n), treatment = rep_len(c("read", "skim"), n),
      reason = paste("section", seq_len(n)), stringsAsFactors = FALSE)), auto_unbox = TRUE)))
  }
  if (has("Decompose text into standalone propositions")) {
    return('{"propositions": ["Revenue was 45.2 million dollars.", "Margin was 41 percent."]}')
  }
  if (has("You screen one document")) {
    return(sprintf(paste0('{"decision":"include","reason":"It reports revenue.",',
                          '"criterion":"Reports a revenue figure","quote":"%s"}'), line))
  }
  if (has("You fill a data-extraction form")) {
    if (has("45.2", all)) {
      return(sprintf(paste0('{"company":"Northwind Instruments","company__quote":"%s",',
                            '"revenue":45.2,"revenue__quote":"%s"}'), line, line))
    }
    return('{"company":null,"company__quote":null,"revenue":null,"revenue__quote":null}')
  }
  if (has("turn a table of studies")) {
    return(paste0('{"claims":[{"claim":"Revenue rose in fiscal 2024.","kind":"finding",',
                  '"supported_by":[1],"contradicted_by":[],"moderator":null,"scope":"one report"}]}'))
  }
  if (has("Group the ones")) return('{"groups":[]}')
  if (has("sections of a")) {
    return(paste0('{"sections":[{"heading":"Findings","brief":"How revenue changed",',
                  '"claims":[1],"rationale":"The one claim."}]}'))
  }
  if (has("situate an excerpt")) return("An excerpt from the annual report of Northwind Instruments.")
  if (has("You extract evidence")) return(line)
  if (has("<studies>", all) || has("section of a")) {
    return("Revenue rose to 45.2 million dollars [study 1].")
  }
  "Revenue was 45.2 million dollars in fiscal 2024, up from 38.7 million."
}

# A mock client with a pinned identity, and a cache that is written to and
# never read. Every request reaches the handler, as it would without the
# cache, and each one the package stores leaves a file named by its key.
#
# The handler empties the cache directory each time it is called, so what it
# finds there is the entry the previous request left: its key. golden_keys()
# collects the last. A request the package declines to store (a failure, a
# reply cut off, one the caller cannot use) leaves no file and gets NA, which
# is a recorded behaviour too.
golden_client <- function(dir) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  keys <- new.env(parent = emptyenv())
  keys$seen <- character(0)
  take <- function() {
    f <- list.files(dir, pattern = "\\.rds$", recursive = TRUE, full.names = TRUE)
    unlink(f)
    k <- sort(sub("\\.rds$", "", basename(f)))
    if (length(k) > 1L) stop("golden: more than one cache entry written by one request")
    if (length(k)) k else NA_character_
  }
  n <- 0L
  handler <- function(messages, params) {
    if (n > 0L) keys$seen <- c(keys$seen, take())
    n <<- n + 1L
    golden_reply(messages, params)
  }
  cl <- harnessr::gr_mock_client(handler)
  # The mock draws a fresh id per client, and the id is part of every cache
  # key, embedding key and corpus key. Pinned, two runs key alike.
  cl$.client_id <- "golden-mock"
  cl <- harnessr::gr_cache_client(cl, harnessr::gr_cache(dir, read = FALSE, write = TRUE))
  attr(cl, "golden_keys") <- function() {
    if (n > length(keys$seen)) keys$seen <- c(keys$seen, take())
    keys$seen
  }
  cl
}

golden_keys <- function(cl) attr(cl, "golden_keys")()

# ---------------------------------------------------------------------------
# One run, recorded.
# ---------------------------------------------------------------------------

golden_call_summary <- function(call, key, paths) {
  msgs <- golden_scrub(lapply(call$messages, function(m) list(role = m$role, content = m$content)),
                       paths)
  full <- golden_scrub(call$params, paths)
  params <- full
  schema <- params$schema
  params$schema <- NULL
  list(
    label = call$label,
    model = params$model,
    params = params,
    schema = if (is.null(schema)) NULL else golden_hash(schema),
    roles = I(vapply(msgs, function(m) m$role, character(1))),
    chars = I(vapply(msgs, function(m) nchar(m$content, type = "chars"), integer(1))),
    messages = golden_hash(msgs),
    request = golden_hash(list(label = call$label, messages = msgs, params = full)),
    cache_key = key
  )
}

golden_trace <- function(trace, paths) {
  if (!inherits(trace, "gr_trace")) return(NULL)
  tr <- jsonlite::parse_json(harnessr::as_json(trace), simplifyVector = FALSE)
  tr$steps <- lapply(tr$steps, function(st) {
    if (!is.null(st$prompt)) st$prompt <- golden_hash(golden_scrub(st$prompt, paths))
    if (!is.null(st$response)) st$response <- golden_hash(golden_scrub(st$response, paths))
    st
  })
  golden_scrub(tr, paths)
}

# Run `expr(client)` from a clean state and record it. `result` turns what the
# run returned into the plain data whose hash is kept.
golden_run <- function(expr, result = function(x) NULL) {
  old <- harnessr::gr_options()
  # The document layer's registries, then the core's.
  st <- harnessr:::gr_state
  slots <- c("extractors", "cleaners", "segmenters", "readers", "embedders", "protocols")
  snap <- stats::setNames(lapply(slots, function(s) st[[s]]), slots)
  core <- harnessr:::hr_state
  core_slots <- c("models", "model_patterns")
  core_snap <- stats::setNames(lapply(core_slots, function(s) core[[s]]), core_slots)
  on.exit({
    for (s in names(snap)) st[[s]] <- snap[[s]]
    for (s in names(core_snap)) core[[s]] <- core_snap[[s]]
    harnessr::gr_options(old)
    harnessr::gr_flush_caches()
  }, add = TRUE)
  # The defaults, whatever an earlier test or the session set.
  harnessr::gr_options(harnessr:::gr_defaults)
  harnessr::gr_options(verbose = FALSE)
  harnessr::gr_flush_caches()
  dir <- tempfile("golden-cache")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  cl <- golden_client(dir)
  out <- suppressWarnings(suppressMessages(expr(cl)))
  paths <- golden_paths()
  calls <- cl$calls()
  keys <- golden_keys(cl)
  list(
    calls = Map(golden_call_summary, calls, keys, MoreArgs = list(paths = paths)),
    trace = golden_trace(golden_find_trace(out), paths),
    result = golden_hash(golden_scrub(result(out), paths))
  )
}

golden_find_trace <- function(x) {
  if (inherits(x, "gr_trace")) return(x)
  if (is.list(x) && inherits(x[["trace", exact = TRUE]], "gr_trace")) return(x$trace)
  tr <- attr(x, "trace", exact = TRUE)
  if (inherits(tr, "gr_trace")) return(tr)
  NULL
}

# ---------------------------------------------------------------------------
# What is recorded.
# ---------------------------------------------------------------------------

golden_answer <- function(ans) list(answer = ans$answer)

# Each shipped recipe through answer_document(), plus "auto", its default.
golden_recipe_runs <- function() {
  recipes <- c(names(harnessr::gr_recipes()), "auto")
  stats::setNames(lapply(recipes, function(r) {
    function() golden_run(function(cl) {
      harnessr::answer_document(harnessr::readgpt_example(), golden_question, r, client = cl)
    }, golden_answer)
  }), paste0("recipe-", recipes))
}

# Each built-in reader on chunks small enough that the multi-call readers make
# more than one call; the recipes above read the example in one chunk.
#
# extract and screen are left out: they are the extract and screen review
# stages, recorded under stage-*. The list is written out rather than read
# from the registry because other test files register readers of their own
# in the same session; test-golden.R checks it against the readers the package
# registers when it loads, so a new built-in reader fails until it is recorded.
golden_readers <- c("ensemble", "hierarchical", "iterative", "map_reduce", "preview", "refine",
                    "rerank", "retrieve", "skim", "stuff")

# The names of the readers the package registers when it loads, read from the
# gr_register_reader() calls in its registration function rather than from the
# registry, which tests may have added to.
golden_builtin_readers <- function() {
  found <- character(0)
  walk <- function(e) {
    if (is.call(e)) {
      if (identical(e[[1L]], as.name("gr_register_reader")) && is.character(e[[2L]])) {
        found <<- c(found, e[[2L]])
      }
      for (a in as.list(e)[-1L]) if (!missing(a)) walk(a)
    }
  }
  walk(body(utils::getFromNamespace("register_builtin_readers", "harnessr")))
  sort(unique(found))
}

golden_reader_runs <- function() {
  readers <- golden_readers
  spec <- function(r) {
    if (identical(r, "ensemble")) {
      return(harnessr::gr_read_spec(r, members = c("retrieve", "map_reduce", "refine")))
    }
    harnessr::gr_read_spec(r)
  }
  stats::setNames(lapply(readers, function(r) {
    function() golden_run(function(cl) {
      rec <- harnessr::gr_recipe(paste0("golden-", r),
                                segment = list(method = "paragraph", max_tokens = 120),
                                read = spec(r))
      harnessr::answer_document(harnessr::readgpt_example(), golden_question, rec, client = cl)
    }, golden_answer)
  }), paste0("reader-", readers))
}

golden_protocol <- function() {
  harnessr::gr_protocol(
    "golden",
    question = "How did revenue change?",
    include = "Reports a revenue figure",
    fields = harnessr::gr_fields(
      company = "The company the report covers",
      revenue = harnessr::gr_field("Revenue in millions of dollars", type = "number")),
    outline = c(Findings = "How revenue changed"))
}

# The review stages, each run on its own with its inputs built by the stage
# before it. The upstream stages are run with a client of their own, so each
# record holds only its own stage's requests.
golden_stage_runs <- function() {
  ex <- function() harnessr::readgpt_example()
  upstream <- function() {
    tmp <- golden_client(tempfile("golden-up"))
    p <- golden_protocol()
    s <- harnessr::gr_screen(ex(), p, client = tmp)
    x <- harnessr::gr_extract(s, p, client = tmp)
    cm <- harnessr::gr_claims(x, question = p$question, client = tmp)
    list(p = p, s = s, x = x, cm = cm, o = harnessr::gr_outline(cm, client = tmp))
  }
  quietly <- function(e) suppressWarnings(suppressMessages(e))
  tab <- function(x) {
    t <- x$table
    t[, setdiff(names(t), c("path", "source")), drop = FALSE]
  }
  list(
    `stage-screen` = function() golden_run(function(cl) {
      harnessr::gr_screen(ex(), golden_protocol(), client = cl)
    }, function(s) tab(s)),
    `stage-extract` = function() golden_run(function(cl) {
      up <- quietly(upstream())
      harnessr::gr_extract(up$s, up$p, client = cl)
    }, function(x) tab(x)),
    `stage-claims` = function() golden_run(function(cl) {
      up <- quietly(upstream())
      harnessr::gr_claims(up$x, question = up$p$question, client = cl)
    }, function(cm) cm$claims),
    # gr_outline() records into the trace of the claims it is given, so that
    # trace, holding the claims stage's step and then the outline's, is the
    # one kept.
    `stage-outline` = function() golden_run(function(cl) {
      up <- quietly(upstream())
      o <- harnessr::gr_outline(up$cm, client = cl)
      list(outline = o, trace = up$cm$trace)
    }, function(x) {
      o <- x$outline
      list(sections = unclass(o)[seq_along(o)], claims = attr(o, "claims"),
           rationale = attr(o, "rationale"), closing = attr(o, "closing"))
    }),
    `stage-synthesise` = function() golden_run(function(cl) {
      up <- quietly(upstream())
      harnessr::gr_synthesise(up$x, protocol = up$p, outline = up$o, claims = up$cm, client = cl)
    }, function(r) list(text = r$text))
  )
}

golden_runs <- function() c(golden_recipe_runs(), golden_reader_runs(), golden_stage_runs())

# ---------------------------------------------------------------------------
# The exported API.
# ---------------------------------------------------------------------------

# A function's arguments in order, each as it would be written in its
# signature: "x" for one without a default, "recipe = \"auto\"" for one with.
# An array, not an object, because the order is part of the API: a call that
# passes arguments by position depends on it.
golden_formals <- function(f) {
  fm <- formals(f)
  # An argument without a default is the empty symbol, which cannot be bound
  # to a name without making that name a missing argument, so it is tested
  # where it stands.
  vapply(seq_along(fm), function(i) {
    if (identical(fm[[i]], quote(expr = ))) return(names(fm)[i])
    paste(names(fm)[i], "=", paste(deparse(fm[[i]], width.cutoff = 500L), collapse = "\n"))
  }, character(1))
}

golden_api <- function() {
  ns <- asNamespace("harnessr")
  exports <- sort(getNamespaceExports("harnessr"), method = "radix")
  fun <- lapply(stats::setNames(exports, exports), function(nm) {
    obj <- get(nm, envir = ns)
    if (is.function(obj)) {
      list(type = "function", formals = I(golden_formals(obj)))
    } else {
      list(type = class(obj)[1])
    }
  })
  s3 <- getNamespaceInfo(ns, "S3methods")
  s3 <- s3[order(s3[, 1], s3[, 2], method = "radix"), , drop = FALSE]
  methods <- lapply(seq_len(nrow(s3)), function(i) {
    impl <- if (is.na(s3[i, 3])) paste(s3[i, 1], s3[i, 2], sep = ".") else s3[i, 3]
    list(generic = s3[i, 1], class = s3[i, 2],
         formals = I(golden_formals(get(impl, envir = ns))))
  })
  names(methods) <- paste(s3[, 1], s3[, 2], sep = ".")
  list(exports = fun, s3methods = methods)
}

# ---------------------------------------------------------------------------
# Writing and comparing.
# ---------------------------------------------------------------------------

golden_compute <- function() {
  runs <- lapply(golden_runs(), function(f) f())
  c(runs, list(api = golden_api()))
}

golden_write <- function(records, dir) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  old <- list.files(dir, pattern = "\\.json$", full.names = TRUE)
  unlink(old)
  for (nm in names(records)) {
    con <- file(file.path(dir, paste0(nm, ".json")), open = "wb")
    writeBin(charToRaw(paste0(golden_json(records[[nm]], pretty = TRUE), "\n")), con)
    close(con)
  }
  invisible(file.path(dir, paste0(names(records), ".json")))
}

# A record as it reads back from its fixture, so the two compare like for like.
golden_roundtrip <- function(x) {
  jsonlite::parse_json(golden_json(x), simplifyVector = FALSE)
}

golden_read <- function(path) {
  jsonlite::parse_json(paste(readLines(path, encoding = "UTF-8", warn = FALSE), collapse = "\n"),
                       simplifyVector = FALSE)
}

# Every field that differs, as "path: fixture -> now", at most `max` of them.
golden_diff <- function(old, new, path = "", max = 40L) {
  out <- character(0)
  show <- function(v) {
    s <- if (is.null(v)) "<absent>" else as.character(jsonlite::toJSON(v, auto_unbox = TRUE,
                                                                      null = "null"))
    if (nchar(s) > 80L) paste0(substr(s, 1L, 77L), "...") else s
  }
  walk <- function(a, b, p) {
    if (length(out) >= max) return(invisible())
    if (is.list(a) && is.list(b)) {
      na <- names(a); nb <- names(b)
      if (!is.null(na) || !is.null(nb)) {
        for (k in union(na, nb)) walk(a[[k]], b[[k]], paste0(p, if (nzchar(p)) "." else "", k))
      } else {
        if (length(a) != length(b)) {
          out <<- c(out, sprintf("%s: length %d -> %d", p, length(a), length(b)))
        }
        for (i in seq_len(min(length(a), length(b)))) walk(a[[i]], b[[i]], sprintf("%s[%d]", p, i))
      }
      return(invisible())
    }
    if (!identical(a, b)) out <<- c(out, sprintf("%s: %s -> %s", p, show(a), show(b)))
  }
  walk(old, new, path)
  out
}
