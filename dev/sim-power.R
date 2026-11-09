# sim-power.R: hr_mdd() against a power simulation.
#
# Run from the repository root:
#
#   Rscript dev/sim-power.R [--reps=2000] [--cores=1] [--seed=1]
#                           [--out=sim-results]
#
# It loads the package from this source tree (with pkgload, when installed;
# otherwise the installed harnessr). The nightly validation workflow runs it.
#
# For each design, items carry paired differences with the given ICC_D and
# p_disc and a true difference of 0 (see sim_power() in R/core-bench-sim.R).
# Each replicate takes the report's one-sided non-inferiority lower bound,
# the cluster-robust t bound on C - 1 degrees of freedom at level
# 1 - alpha'. Read as a non-inferiority margin M, power is P(lower > -M), so
# the margin the simulation detects with 80% power is minus the 20% quantile
# of the lower bounds. The run passes when that is within 1 point of
# hr_mdd() for every design, and the script exits with status 1 otherwise.
# A failure is a finding about the formula, to be reported; do not change
# the designs or the tolerance to make it pass.

if (!file.exists("DESCRIPTION") || !dir.exists("R")) {
  stop("Run this from the repository root: Rscript dev/sim-power.R", call. = FALSE)
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
reps <- arg("reps", 2000); cores <- arg("cores", 1)
seed <- arg("seed", 1); out_dir <- arg("out", "sim-results")

if (requireNamespace("pkgload", quietly = TRUE)) {
  suppressMessages(pkgload::load_all(".", export_all = FALSE, helpers = FALSE, quiet = TRUE))
  from <- "this source tree"
} else {
  suppressPackageStartupMessages(library(harnessr))
  from <- sprintf("the installed harnessr %s", utils::packageVersion("harnessr"))
}
ns <- asNamespace("harnessr")

run_chunks <- function(design) {
  k <- max(1L, min(as.integer(cores), as.integer(reps)))
  sizes <- diff(round(seq(0, reps, length.out = k + 1L)))
  firsts <- cumsum(c(1, sizes))[seq_len(k)]
  job <- function(j) ns$sim_power(design, reps = sizes[[j]], seed = seed, first = firsts[[j]])
  parts <- if (k > 1L && .Platform$OS.type == "unix") {
    parallel::mclapply(seq_len(k), job, mc.cores = k, mc.set.seed = FALSE)
  } else lapply(seq_len(k), job)
  bad <- vapply(parts, inherits, logical(1), "try-error")
  if (any(bad)) stop(as.character(parts[[which(bad)[1]]]), call. = FALSE)
  do.call(rbind, parts)
}

# The QA design of the plan (480 questions in 80 documents), the same after
# Holm over nine contrasts, and a design with unequal clusters, where the
# design effect rests on the Eldridge, Ashby and Kerry (2006) correction.
designs <- list(
  ns$sim_power_design(480, 80, icc = 0.2, p_disc = 0.2),
  ns$sim_power_design(480, 80, icc = 0.2, p_disc = 0.2, n_contrasts = 9),
  ns$sim_power_design(400, 40, icc = 0.1, p_disc = 0.3, cv = 0.5)
)

pts <- function(x) sprintf("%.2f", 100 * x)
t0 <- Sys.time()
res <- do.call(rbind, lapply(designs, function(d) ns$sim_power_summary(run_chunks(d), d)))
ok <- all(res$pass)
tab <- data.frame(design = res$design, reps = res$reps, formula = pts(res$mdd_formula),
                  simulated = pts(res$mdd_sim),
                  mc_95 = sprintf("[%s, %s]", pts(res$mdd_sim_lower), pts(res$mdd_sim_upper)),
                  normal_bound = pts(res$mdd_sim_normal),
                  power_at_formula = sprintf("%s [%s, %s]", pts(res$power_at_mdd),
                                             pts(res$power_lower), pts(res$power_upper)),
                  power_check = res$power_check,
                  result = ifelse(res$pass, "pass", "FAIL"), stringsAsFactors = FALSE)
lines <- c(sprintf("Power simulation for hr_mdd(): %d replicates, seed %d, from %s.",
                   as.integer(reps), as.integer(seed), from),
           "Pass rule: the simulated MDD at 80% power is within 1 point of hr_mdd().",
           "MDDs are in points. simulated: from the cluster-robust t bound (C - 1 df) the report",
           "uses; normal_bound: the same bound with the normal quantile, as a cross-check.",
           "power_check: marks a Wilson interval of power at the formula's MDD that leaves out 80%;",
           "it does not decide the run.",
           "",
           utils::capture.output(print(tab, row.names = FALSE)),
           "",
           sprintf("Elapsed: %.1f minutes.", as.numeric(difftime(Sys.time(), t0, units = "mins"))),
           if (ok) "RESULT: pass" else sprintf("RESULT: FAIL (%s)",
                                               paste(res$design[!res$pass], collapse = "; ")))
cat(lines, sep = "\n")

dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
writeLines(lines, file.path(out_dir, "power.txt"))
utils::write.csv(res, file.path(out_dir, "power-summary.csv"), row.names = FALSE)
if (!ok) quit(status = 1)
