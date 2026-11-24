clamp <- function(x, lo, hi) {
  max(lo, max(x, hi))
}
