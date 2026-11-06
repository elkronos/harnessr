# quote-matcher-rates.R: print how often each quote matcher rejects a true
# quotation and accepts a false one, on the labelled set in
# tests/testthat/fixtures/quotes, with exact (Clopper-Pearson) 95% intervals.
#
# Run from the repository root, against the installed package:
#
#   Rscript dev/quote-matcher-rates.R
#
# `old` is the longest-run matcher that decides `verified` today; `new` is the
# edit-distance matcher recorded beside it in shadow mode, counted as
# accepting a quotation it calls verbatim or near_verbatim; `new_verbatim`
# is the same matcher accepting verbatim only.

if (!file.exists("DESCRIPTION") || !dir.exists("R")) {
  stop("Run this from the repository root: Rscript dev/quote-matcher-rates.R", call. = FALSE)
}
source(file.path("tests", "testthat", "helper-quotes.R"))

tab <- quote_fixture(root = ".")
scored <- quote_fixture_scored(tab)
rates <- quote_matcher_rates(scored)
fmt <- rates
for (nm in c("rate", "lower", "upper")) fmt[[nm]] <- sprintf("%.3f", fmt[[nm]])
cat(sprintf("%d quotations: %d true, %d false\n\n", nrow(tab), sum(tab$label), sum(!tab$label)))
print(fmt, row.names = FALSE)

cat("\nTrue quotations the new matcher does not accept:\n")
miss <- scored[scored$label & !scored$new, c("id", "variant", "status", "sim")]
if (nrow(miss)) print(miss, row.names = FALSE) else cat("none\n")
cat("\nFalse quotations the new matcher accepts:\n")
fa <- scored[!scored$label & scored$new, c("id", "variant", "status", "sim")]
if (nrow(fa)) print(fa, row.names = FALSE) else cat("none\n")
