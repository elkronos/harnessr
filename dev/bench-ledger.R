# bench-ledger.R: time appending steps to a trace, with the package's appends
# and with the old c() appends they replaced.
#
# Run from the repository root, after installing the package from this tree:
#
#   Rscript dev/bench-ledger.R [n]
#
# For each way of appending it times:
#   - n notes on one trace (trace_note());
#   - n child traces, each given the parent's draw through
#     trace_inherit_draw(), holding one note and folded into the parent with
#     trace_absorb(), as a stage that records on its own trace does.
# n defaults to 5000. It writes nothing; it prints the timings.

args <- commandArgs(trailingOnly = TRUE)
n <- if (length(args)) as.integer(args[[1]]) else 5000L
stopifnot(!is.na(n), n >= 1L)

ns <- asNamespace("harnessr")

old_push <- function(trace, new) {
  trace$steps <- c(trace$steps, new)
  invisible(NULL)
}

# The package's function with the old append put back.
with_old_push <- function(f) {
  env <- new.env(parent = ns)
  env$trace_push_steps <- old_push
  environment(f) <- env
  f
}

fns <- list(
  indexed = list(note = ns$trace_note, absorb = ns$trace_absorb),
  c_append = list(note = with_old_push(ns$trace_note),
                  absorb = with_old_push(ns$trace_absorb))
)

time_notes <- function(f) {
  tr <- harnessr::gr_trace()
  s <- system.time(for (i in seq_len(n)) f$note(tr, "note", list(i = i)))[["elapsed"]]
  stopifnot(length(tr$steps) == n)
  s
}

time_children <- function(f) {
  parent <- harnessr::gr_trace()
  parent$draw_index <- 2L
  parent$draw_scope <- "armA"
  # Made before the clock starts: gr_trace() reads the options and the
  # package version, which costs more than the appends being timed.
  kids <- lapply(seq_len(n), function(i) harnessr::gr_trace())
  s <- system.time(for (i in seq_len(n)) {
    child <- ns$trace_inherit_draw(kids[[i]], parent)
    f$note(child, "child.note")
    f$absorb(parent, child)
  })[["elapsed"]]
  stopifnot(length(parent$steps) == n)
  s
}

res <- do.call(rbind, lapply(names(fns), function(k) {
  data.frame(append = k, n = n,
             notes_s = time_notes(fns[[k]]),
             children_s = time_children(fns[[k]]))
}))
print(res, row.names = FALSE)
