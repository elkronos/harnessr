last_n <- function(x, n) {
  x[seq.int(length(x) - n + 1L, length.out = n)]
}
