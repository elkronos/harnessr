# helper-listings.R: what the module registries show today, for
# test-registry-snapshot.R and dev/record-listings.R.
#
# The record is kept in fixtures/registry/listings.rds. It pins what a later
# change to the registries must keep: the columns, column types, row order and
# row names of each gr_*() listing, the `registered` stamp of every built-in
# cleaner and extractor, and the hash of the code an ingestion would run, which
# is part of the ingest cache key. Nothing in this file runs on load.

listings_functions <- c("gr_readers", "gr_segmenters", "gr_cleaners", "gr_extractors",
                        "gr_embedders", "gr_protocols")

# Columns whose values depend on the machine: whether an extractor's package
# is installed. Their names and types are kept, their values are not.
listings_machine_columns <- list(gr_extractors = "available")

# Fixed ingest specs, each with the source it is asked about.
listings_ingest_cases <- function() {
  list(
    default_txt = list(spec = harnessr::gr_ingest_spec(), is_path = TRUE, url = FALSE,
                       source = "report.txt"),
    academic_md = list(spec = harnessr::gr_ingest_spec(clean = "academic"), is_path = TRUE,
                       url = FALSE, source = "paper.md"),
    forced_html = list(spec = harnessr::gr_ingest_spec(extractor = "html"), is_path = TRUE,
                       url = FALSE, source = "page.txt"),
    url = list(spec = harnessr::gr_ingest_spec(), is_path = FALSE, url = TRUE,
               source = "https://example.org/a"),
    inline = list(spec = harnessr::gr_ingest_spec(clean = "none"), is_path = FALSE,
                  url = FALSE, source = "Some text."))
}

# Every function in `x` replaced by what it is: the cleaner or extractor it
# is registered as, or the namespace object it is. So the code an ingestion
# would run can be compared without deparsing it.
listings_fn_names <- function(x, ns = asNamespace("harnessr")) {
  if (is.function(x)) {
    for (kind in c("cleaners", "extractors")) {
      reg <- ns$gr_state[[kind]]
      for (nm in names(reg)) {
        if (identical(reg[[nm]]$fn, x)) return(sprintf("<%s:%s>", kind, nm))
      }
    }
    for (nm in ls(ns, all.names = TRUE)) {
      if (identical(get(nm, envir = ns), x)) return(paste0("<fn:", nm, ">"))
    }
    return("<fn:anonymous>")
  }
  if (is.list(x)) {
    out <- lapply(x, listings_fn_names, ns = ns)
    attributes(out) <- attributes(x)
    return(out)
  }
  x
}

# The deparsed text of every function in `x`, hashed: when this matches the
# record, this R deparses the code as the recording R did, and the full hash
# must match too.
listings_fn_text <- function(x) {
  fns <- character(0)
  walk <- function(v) {
    if (is.function(v)) fns <<- c(fns, paste(deparse(v), collapse = "\n"))
    else if (is.list(v)) for (e in v) walk(e)
  }
  walk(x)
  harnessr:::hr_hash(fns)
}

# hr_hash() of `x` as the ingest cache computes it, except that a closure's
# environment, which hr_hash() names by its address when it has no name, is
# named the same in every session. The rest of the key, the code and the names
# of named environments, is as hr_hash() sees it.
listings_key_hash <- function(x) {
  ns <- asNamespace("harnessr")
  parts <- ns$hash_parts(x, envid = ns$env_name)
  parts <- gsub("<environment: 0x[0-9a-f]+>", "<environment>", parts)
  digest::digest(charToRaw(enc2utf8(paste(parts, collapse = "\u0001"))), algo = "sha256",
                 serialize = FALSE)
}

listings_snapshot <- function() {
  ns <- asNamespace("harnessr")
  listing <- lapply(stats::setNames(listings_functions, listings_functions), function(f) {
    x <- get(f, envir = ns)()
    data <- x
    drop <- listings_machine_columns[[f]]
    if (length(drop)) data <- data[, setdiff(names(data), drop), drop = FALSE]
    list(class = class(x), names = names(x),
         types = vapply(x, typeof, character(1)),
         rownames = attr(x, "row.names"),
         data = data)
  })
  st <- ns$gr_state
  stamps <- list(
    cleaners = vapply(st$cleaners, function(e) as.numeric(e$registered), numeric(1)),
    extractors = vapply(st$extractors, function(e) as.numeric(e$registered), numeric(1)))
  ingest <- lapply(listings_ingest_cases(), function(k) {
    code <- ns$ingest_code(k$spec, k$is_path, k$url, k$source)
    list(hash = listings_key_hash(code), fn_text = listings_fn_text(code),
         named = listings_fn_names(code))
  })
  list(listing = listing, stamps = stamps, ingest = ingest)
}

listings_path <- function(root = NULL) {
  if (!is.null(root)) {
    return(file.path(root, "tests", "testthat", "fixtures", "registry", "listings.rds"))
  }
  testthat::test_path("fixtures", "registry", "listings.rds")
}
