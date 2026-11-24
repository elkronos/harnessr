clamp <- function(x, lo, hi) {
  max(lo, min(x, hi))
}
