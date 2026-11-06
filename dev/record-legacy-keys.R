# record-legacy-keys.R: write tests/testthat/fixtures/legacy-0.6.0/.
#
# The fixture is a response cache and a recording made before the cache key
# moved to harnessr-cache-v3 (sha256) and the replay key to harnessr-replay-v2.
# test-compat-legacy-keys.R checks that the current code still answers every call in
# it through the old keys. So it has to be written by the old code, once:
#
#   mkdir -p /tmp/harnessr-c91b04b /tmp/lib-c91b04b
#   git archive c91b04b | tar -x -C /tmp/harnessr-c91b04b
#   R CMD INSTALL -l /tmp/lib-c91b04b /tmp/harnessr-c91b04b
#   R_LIBS=/tmp/lib-c91b04b:$R_LIBS Rscript dev/record-legacy-keys.R
#
# run from the root of the current tree, which supplies the helper and the
# output directory. It stops unless the harnessr it loads still writes
# readgpt-cache-v2 keys. Rerunning it with a later build would record new keys
# and make the test check nothing.

if (!file.exists("DESCRIPTION") || !dir.exists(file.path("tests", "testthat"))) {
  stop("Run this from the repository root: Rscript dev/record-legacy-keys.R", call. = FALSE)
}
Sys.setenv(OPENAI_API_KEY = "")
suppressPackageStartupMessages(library(harnessr))
if (!any(grepl("readgpt-cache-v2", deparse(harnessr:::cache_key), fixed = TRUE))) {
  stop("The loaded harnessr does not write readgpt-cache-v2 keys; install the build before ",
       "the key change (commit c91b04b) and point R_LIBS at it.", call. = FALSE)
}

source(file.path("tests", "testthat", "helper-legacy-keys.R"), local = TRUE)

out <- legacy_keys_dir(".")
# Only this script's own files: the directory also holds the other 0.6.0
# fixtures, which are written elsewhere.
unlink(file.path(out, c("cache", "recording.json")), recursive = TRUE)
dir.create(out, recursive = TRUE, showWarnings = FALSE)

gr_options(harnessr:::gr_defaults)
gr_options(verbose = FALSE)

# The cache: every call written under its old key. The repeated prompt is a
# hit, so six calls leave five entries.
cl <- gr_cache_client(legacy_keys_client(), gr_cache(file.path(out, "cache")))
invisible(legacy_keys_calls(cl))

# The recording: the same calls, uncached, so the repeated prompt is recorded
# twice. Saved as gr_trace_save() writes it.
tr <- gr_trace(run_id = "legacy-keys-fixture")
invisible(legacy_keys_calls(legacy_keys_client(), tr))
gr_trace_save(tr, file.path(out, "recording.json"))

cat(sprintf("Recorded with harnessr %s: %d cache entries, %d recorded calls, in %s\n",
            utils::packageVersion("harnessr"),
            length(list.files(file.path(out, "cache"), recursive = TRUE)),
            length(tr$steps), out))
