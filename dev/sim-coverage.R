# sim-coverage.R: coverage of the intervals hr_report() gives, on simulated
# benchmarks with a known answer.
#
# Run from the repository root:
#
#   Rscript dev/sim-coverage.R [--reps=2000] [--B=2000] [--cores=1] [--seed=1]
#                              [--out=sim-results]
#
# It loads the package from this source tree (with pkgload, when installed;
# otherwise the installed harnessr). The nightly validation workflow runs it;
# it is too slow for the test suite.
#
# Each replicate simulates a clustered corpus with a known effect, document
# ICC and run variance (see sim_design() in R/core-bench-sim.R), reports it
# with hr_report() and records whether each interval holds the true value.
# Two regimes: a large design (386 items in 40 clusters, studentised cluster
# bootstrap for accuracy) and a small one (50 items in 10 clusters, the
# cluster-robust t interval on the logit scale; the Korn and Graubard interval
# of method = "exact" is printed beside it without deciding the run). The
# paired difference is the cluster-robust t interval on C - 1 degrees of
# freedom in both, as the report gives it.
#
# The pass rule, for every interval the report gives by default: the Wilson
# 95% interval of coverage over the replicates contains 0.95 and its lower end
# is at least 0.93. The script exits with status 1 when any fails. A failure
# is a finding about the method, to be reported; do not change the design or
# the rule to make it pass.

if (!file.exists("DESCRIPTION") || !dir.exists("R")) {
  stop("Run this from the repository root: Rscript dev/sim-coverage.R", call. = FALSE)
}
Sys.setenv(OPENAI_API_KEY = "")
options(width = 200)

arg <- function(name, default) {
  a <- commandArgs(trailingOnly = TRUE)
  hit <- grep(paste0("^--", name, "="), a, value = TRUE)
  if (!length(hit)) return(default)
  v <- sub(paste0("^--", name, "="), "", hit[[length(hit)]])
  if (is.numeric(default)) as.numeric(v) else v
}
reps <- arg("reps", 2000); B <- arg("B", 2000); cores <- arg("cores", 1)
seed <- arg("seed", 1); out_dir <- arg("out", "sim-results")

if (requireNamespace("pkgload", quietly = TRUE)) {
  suppressMessages(pkgload::load_all(".", export_all = FALSE, helpers = FALSE, quiet = TRUE))
  from <- "this source tree"
} else {
  suppressPackageStartupMessages(library(harnessr))
  from <- sprintf("the installed harnessr %s", utils::packageVersion("harnessr"))
}
ns <- asNamespace("harnessr")

# Replicates split into one chunk per core. Each replicate has its own seed,
# so the split does not change the result.
run_chunks <- function(design) {
  k <- max(1L, min(as.integer(cores), as.integer(reps)))
  sizes <- diff(round(seq(0, reps, length.out = k + 1L)))
  firsts <- cumsum(c(1, sizes))[seq_len(k)]
  job <- function(j) ns$sim_coverage(design, reps = sizes[[j]], seed = seed, B = B,
                                     first = firsts[[j]])
  parts <- if (k > 1L && .Platform$OS.type == "unix") {
    parallel::mclapply(seq_len(k), job, mc.cores = k, mc.set.seed = FALSE)
  } else lapply(seq_len(k), job)
  bad <- vapply(parts, inherits, logical(1), "try-error")
  if (any(bad)) stop(as.character(parts[[which(bad)[1]]]), call. = FALSE)
  do.call(rbind, parts)
}

designs <- list(large = ns$sim_design("large"), small = ns$sim_design("small"))
pct <- function(x) sprintf("%.1f", 100 * x)

lines <- c(sprintf("Coverage simulation: %d replicates, B = %d, seed %d, from %s.",
                   as.integer(reps), as.integer(B), as.integer(seed), from),
           "Pass rule: the Wilson 95% interval of coverage contains 95% and its lower end is >= 93%.",
           "")
summaries <- list(); all_reps <- list()
t0 <- Sys.time()
for (nm in names(designs)) {
  d <- designs[[nm]]
  x <- run_chunks(d)
  s <- ns$sim_coverage_summary(x)
  x$regime <- nm; s$regime <- nm
  all_reps[[nm]] <- x; summaries[[nm]] <- s
  lines <- c(lines,
    sprintf("Regime %s: %d items in %d clusters, %d runs; true accuracy %s = %s, %s = %s, difference %s points.",
            nm, sum(d$sizes), length(d$sizes), d$runs, names(d$accuracy)[1], pct(d$accuracy[[1]]),
            names(d$accuracy)[2], pct(d$accuracy[[2]]), pct(d$truth[["diff"]])),
    sprintf("  Latent shares: document %.2f (shared %.2f, per arm %.2f), item %.2f, item x arm %.2f, run %.2f.",
            d$icc_doc, d$var[["doc"]], d$var[["doc_arm"]], d$var[["item"]], d$var[["item_arm"]],
            d$var[["run"]]),
    "")
  tab <- data.frame(quantity = s$quantity, arm = s$arm, method = s$method,
                    decides = ifelse(s$gate, "yes", "no"), reps = s$reps,
                    coverage = pct(s$coverage),
                    mc_95 = sprintf("[%s, %s]", pct(s$mc_lower), pct(s$mc_upper)),
                    below = pct(s$below), above = pct(s$above),
                    width = pct(s$width), bias = sprintf("%+.2f", 100 * s$bias),
                    result = ifelse(s$gate, ifelse(s$pass, "pass", "FAIL"),
                                    ifelse(s$pass, "within", "outside")),
                    stringsAsFactors = FALSE)
  lines <- c(lines, paste0("  ", utils::capture.output(print(tab, row.names = FALSE))), "")
}
gate <- do.call(rbind, summaries)
gate <- gate[gate$gate, ]
ok <- all(gate$pass)
lines <- c(lines,
  "Coverage, width and bias are in percentage points; below and above are the shares of",
  "intervals lying wholly below or above the true value. Rows that do not decide the run",
  "show whether they meet the pass rule as within or outside, for information.",
  sprintf("Elapsed: %.1f minutes.", as.numeric(difftime(Sys.time(), t0, units = "mins"))),
  if (ok) "RESULT: pass" else sprintf("RESULT: FAIL (%s)",
    paste(sprintf("%s %s %s", gate$regime[!gate$pass], gate$quantity[!gate$pass],
                  gate$arm[!gate$pass]), collapse = "; ")))
cat(lines, sep = "\n")

dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
writeLines(lines, file.path(out_dir, "coverage.txt"))
utils::write.csv(do.call(rbind, summaries), file.path(out_dir, "coverage-summary.csv"),
                 row.names = FALSE)
utils::write.csv(do.call(rbind, all_reps), file.path(out_dir, "coverage-replicates.csv"),
                 row.names = FALSE)
if (!ok) quit(status = 1)
