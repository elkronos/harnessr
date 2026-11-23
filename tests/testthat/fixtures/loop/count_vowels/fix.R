count_vowels <- function(s) {
  sum(strsplit(s, "")[[1]] %in% c("a", "e", "i", "o", "u"))
}
