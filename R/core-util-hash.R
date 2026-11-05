# core-util-hash.R: stable hashes of R values, for cache keys.

#' Deterministic content hash, with a pure-R fallback when digest is absent.
#'
#' Used for cache keys. Never returns NA.
#' @noRd
gr_hash <- function(x) {
  s <- paste(hash_parts(x), collapse = "\u0001")
  if (requireNamespace("digest", quietly = TRUE)) {
    return(digest::digest(s, algo = "xxhash64"))
  }
  hash_fallback(s)
}

#' A deterministic serialisation that carries names at EVERY depth.
#'
#' The previous one was `str(x, max.level = 3L)` joined to
#' `as.character(unlist(x, use.names = TRUE))`, and neither half could see a
#' name nested four levels down: `str()` stops printing at level 3, and
#' `as.character()` drops the names attribute, so `use.names = TRUE` was inert.
#' Two JSON schemas differing only in a leaf's NAME therefore hashed
#' identically, and since the schema is part of the response-cache key, asking
#' for `{result:{headcount}}` after `{result:{revenue}}` returned the revenue
#' figure under the headcount question, marked `cached = TRUE`. The same
#' primitive keys the ingest cache, the corpus store and gr_compare()'s
#' distinctness check, so the blindness was latent in all of them.
#' @noRd
hash_parts <- function(x, prefix = "", depth = 0L) {
  if (depth > 32L) return(paste0(prefix, "=<depth>"))
  if (is.null(x)) return(paste0(prefix, "=<null>"))
  if (is.list(x)) {
    if (!length(x)) return(paste0(prefix, "=<empty:", class(x)[1], ">"))
    nms <- names(x)
    if (is.null(nms)) nms <- rep("", length(x))
    nms <- hash_escape(nms)
    return(c(sprintf("%s=<%s:%d>", prefix, class(x)[1], length(x)),
             unlist(lapply(seq_along(x), function(i) {
               hash_parts(x[[i]],
                          paste0(prefix, "/", if (nzchar(nms[i])) nms[i] else i),
                          depth + 1L)
             }), use.names = FALSE)))
  }
  if (is.function(x)) {
    # as.character() cannot turn a function into text, so every function used
    # to serialise as the bare word "function" and any two hashed alike. A
    # cleaner fixed and registered again under its old name was then served
    # from the ingest cache as the broken one had left it. The code is hashed
    # (deparse() leaves out source references and byte code), and so is where
    # it runs: the same code in two closures can hold different values. A
    # named environment (the global one, a package) goes in by name, so a key
    # built from one is the same in every session; any other by identity.
    return(paste0(prefix, "=function:", paste(deparse(x), collapse = "\n"),
                  "@", env_identity(environment(x))))
  }
  v <- hash_escape(tryCatch(as.character(x), error = function(e) class(x)[1]))
  nms <- hash_escape(names(x))
  paste0(prefix, "=", class(x)[1], ":",
         if (is.null(nms)) "" else paste0("[", paste(nms, collapse = ","), "]"),
         paste(v, collapse = "\u0002"))
}

#' Escape the characters hash_parts() and gr_hash() join with.
#'
#' The elements of a vector are joined with U+0002 and the parts with U+0001,
#' so a string holding either could stand for two: one message whose content
#' was "Say A<U+0002>user<U+0002>Say B" hashed as the two messages "Say A" and
#' "Say B", and the response cache and the replay served one prompt's answer
#' for the other. So U+0003 escapes itself and the two separators, which is
#' reversible, and so never maps two inputs to one. A string with none of the
#' three is left as it is, and every key it was in stays what it was: saved
#' caches, recordings and stores are still found.
#' @noRd
hash_escape <- function(v) {
  if (!length(v)) return(v)
  hit <- which(grepl("[\\x01-\\x03]", v, perl = TRUE, useBytes = TRUE))
  if (!length(hit)) return(v)
  e <- v[hit]
  enc <- Encoding(e)
  e <- gsub("\u0003", "\u0003\u0003", e, fixed = TRUE, useBytes = TRUE)
  e <- gsub("\u0001", "\u00031", e, fixed = TRUE, useBytes = TRUE)
  e <- gsub("\u0002", "\u00032", e, fixed = TRUE, useBytes = TRUE)
  # Only ASCII bytes changed, so the declared encoding still holds.
  Encoding(e) <- enc
  v[hit] <- e
  v
}

#' What a function's environment is, for a hash: its name when it has one,
#' otherwise its address.
#' @noRd
env_identity <- function(env) {
  if (is.null(env)) return("<primitive>")
  nm <- environmentName(env)
  # The package was called readgpt when today's keys were made, and every key
  # that hashes one of its functions includes this name. Hashing the old name
  # keeps those keys stable until the planned key-version change, which will
  # carry a lookup of the old keys.
  if (identical(nm, "harnessr")) return("readgpt")
  if (nzchar(nm)) return(nm)
  utils::capture.output(print.default(env))[1]
}

#' @noRd
hash_fallback <- function(s) {
  # Deliberately not a hand-rolled hash. The previous fallback was an FNV-1a
  # loop seeded above .Machine$integer.max, so bitwXor() returned NA on the
  # first byte and EVERY input hashed identically -- every cache key collided
  # and gr_ingest() returned the first document it had ever seen, whatever file
  # or settings you asked for. A weak replacement risks the same class of
  # silent wrong-document bug, so cache-key hashing has one implementation and
  # `digest` is a hard dependency.
  gr_abort(paste0("The 'digest' package is required for cache-key hashing but is not ",
                  "installed. Install it (install.packages('digest')), or disable ",
                  "caching with gr_options(cache_documents = FALSE, cache_embeddings = FALSE)."),
           class = "gr_missing_dep")
}
