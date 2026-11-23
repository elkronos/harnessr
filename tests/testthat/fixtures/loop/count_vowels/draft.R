count_vowels <- function(s) {
  sum(strsplit(s, "")[[1]] == "a")
}
