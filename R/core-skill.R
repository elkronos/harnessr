# core-skill.R: skills, folders of instructions a person chooses for a step.
#
# hr_skill() reads one skill folder: a SKILL.md file with a short header and
# the instructions, optional text files under references/, and optional
# scripts under scripts/. A skill is given to a step with
# hr_step(skill = ...), and inside a chain its instructions and references
# go into that step's requests as a system message. The package never looks
# for skills on its own and never lets a model choose one; a script is never
# run unless the user wraps it in hr_step_command(). The header is read
# without a YAML parser: only simple `key: value` lines are allowed.

#' The most bytes hr_skill() reads from a folder: SKILL.md, the references
#' and the scripts together. A fixed limit, not a setting.
#' @noRd
.hr_skill_max_bytes <- 2e5

#' The most files hr_skill() reads from references/, and the most it lists
#' from scripts/. A fixed limit, not a setting.
#' @noRd
.hr_skill_max_files <- 50L

#' The header keys hr_skill() keeps; any other key warns.
#' @noRd
.hr_skill_keys <- c("name", "description", "version")

#' Read a skill folder
#'
#' `hr_skill()` reads a skill: a folder you chose that holds instructions
#' for one step of a run. Give the skill to a step with
#' `hr_step(..., skill = s)`; inside [hr_chain()] the step's `ctx$call()` and
#' `ctx$call_json()` then send the skill's instructions and references as a
#' system message before the step's own messages, and `ctx$skill` holds the
#' skill.
#'
#' The folder holds:
#' \describe{
#'   \item{`SKILL.md`}{Required. It starts with a header between two lines
#'     that are exactly `---`. Each header line is `key: value`, with the
#'     value on the same line; matching quotes around it are removed. `name`
#'     is required, and `description` and `version` are kept. Any other key
#'     warns with class `hr_skill_unknown_key` and is ignored. A value that
#'     is indented, nested or spread over lines (`|` or `>`) is an error,
#'     since the header is read without a YAML parser. Everything after the
#'     closing `---` is the instructions.}
#'   \item{`references/`}{Optional text files, added after the
#'     instructions. A file with a nul byte, or that is not UTF-8 text, is an
#'     error. Line endings are read as `"\n"`, so a CRLF copy gives the same
#'     text and hash.}
#'   \item{`scripts/`}{Optional. The scripts are listed by path and never
#'     run. To run one, wrap it yourself in a command step, as in
#'     `hr_step_command("lint", c(rscript, s$scripts[["check.R"]]))`.}
#' }
#'
#' The folder is read only where you point: the package never looks for
#' skills, and a model never chooses one. A file that is a link to
#' somewhere outside the folder is an error, and so are a broken link, a
#' `references/` or `scripts/` folder that is a link to somewhere outside,
#' a link to a folder under either of them, and a folder with more
#' than 50 reference files, more than 50 scripts, or more than 200,000
#' bytes in all. These limits are fixed. All errors have class
#' `hr_bad_skill`.
#'
#' A skill's text goes into the prompt as it is, so a skill from someone
#' else can carry instructions you did not mean to send (prompt injection).
#' Read a skill before you use it.
#'
#' The skill's `hash` covers the header, the instructions, each reference
#' and every byte of each script, so editing any of them changes it. A step
#' given a skill has the hash among its fixed settings and in its
#' fingerprint, so a chain with a skill has a different configuration from
#' the same chain without it, and a benchmark gets a `param.<step>.skill`
#' column naming the skill and the start of its hash.
#'
#' @param path The skill's folder, one string.
#' @return A list of class `hr_skill` with `name`, `description` and
#'   `version` (`NULL` when the header has none), `instructions` (one
#'   string), `references` (a named character vector of file texts, named by
#'   path under `references/`), `scripts` (a named character vector of full
#'   paths, named by path under `scripts/`), `path` (the folder's full path)
#'   and `hash`.
#' @seealso [hr_step()], [hr_chain()], [hr_step_command()], `vignette("compose")`
#' @family harness
#' @export
#' @examples
#' dir <- file.path(tempdir(), "units-skill")
#' dir.create(file.path(dir, "references"), recursive = TRUE, showWarnings = FALSE)
#' writeLines(c("---", "name: units", "description: Give amounts with units.",
#'              "version: 1.0.0", "---",
#'              "Always state the unit and the currency of every amount."),
#'            file.path(dir, "SKILL.md"))
#' writeLines("Write million in full.", file.path(dir, "references", "style.md"))
#' s <- hr_skill(dir)
#' s
#'
#' # In a chain, the step's requests carry the skill as a system message.
#' cl <- hr_mock_client(function(m, p) "45.2 million dollars")
#' ask <- hr_step("ask", function(input, ctx) ctx$call(input)$text, skill = s)
#' chain <- hr_chain(ask = ask, name = "with-skill")
#' chain$params
#' ref <- hr_reference(list(q1 = "What was revenue?"), labels = "45.2 million dollars",
#'                     cluster = "a", split = "test")
#' bench <- hr_benchmark(chain, ref, runs = 5, client = cl, scorer = hr_scorer_exact())
#' sent <- cl$calls()[[1]]$messages
#' vapply(sent, function(m) m$role, "")
#' unique(bench$param.ask.skill)
#' unlink(dir, recursive = TRUE)
hr_skill <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    gr_abort("`path` must be one folder.", class = "hr_bad_skill")
  }
  root <- tryCatch(normalizePath(path, winslash = "/", mustWork = TRUE),
                   error = function(e) {
                     gr_abort(sprintf("The skill folder '%s' does not exist.", path),
                              class = "hr_bad_skill")
                   })
  if (!dir.exists(root)) {
    gr_abort(sprintf("'%s' is a file; a skill is a folder that holds SKILL.md.", path),
             class = "hr_bad_skill")
  }
  what <- sprintf("Skill '%s'", path)
  used <- 0
  read_file <- function(rel) {
    f <- skill_inside(root, rel, what)
    n <- file.size(f)
    used <<- used + n
    if (used > .hr_skill_max_bytes) {
      gr_abort(sprintf("%s holds more than %s bytes; a skill is read whole into the prompt.",
                       what, format(.hr_skill_max_bytes, big.mark = ",", scientific = FALSE)),
               class = "hr_bad_skill")
    }
    readBin(f, "raw", n)
  }
  if (!utils::file_test("-f", file.path(root, "SKILL.md"))) {
    if (dir.exists(file.path(root, "SKILL.md"))) {
      gr_abort(sprintf("%s: SKILL.md is a folder; it must be a file.", what),
               class = "hr_bad_skill")
    }
    gr_abort(sprintf("%s has no SKILL.md.", what), class = "hr_bad_skill")
  }
  text <- skill_text(read_file("SKILL.md"), "SKILL.md", what)
  parsed <- skill_parse(text, what)
  refs <- skill_files(root, "references", what)
  # Line endings are made "\n", as in SKILL.md, so a checkout with CRLF
  # endings gives the same text and the same hash. Scripts keep their bytes.
  references <- vapply(refs, function(rel) {
    gsub("\r\n", "\n", skill_text(read_file(rel), rel, what), fixed = TRUE)
  }, character(1))
  names(references) <- sub("^references/", "", refs)
  scr <- skill_files(root, "scripts", what)
  script_bytes <- lapply(scr, read_file)
  names(script_bytes) <- sub("^scripts/", "", scr)
  scripts <- vapply(scr, function(rel) skill_inside(root, rel, what), character(1))
  names(scripts) <- names(script_bytes)
  header <- parsed$header
  hash <- hr_hash(list(header = header, instructions = parsed$instructions,
                       references = as.list(references), scripts = script_bytes))
  structure(list(name = header$name, description = header$description,
                 version = header$version, instructions = parsed$instructions,
                 references = references, scripts = scripts, path = root, hash = hash),
            class = "hr_skill")
}

#' @export
print.hr_skill <- function(x, ...) {
  cat(sprintf("<hr_skill> %s%s (%s)\n", x$name,
              if (is.null(x$version)) "" else paste(" version", x$version),
              substr(x$hash, 1L, 12L)))
  if (!is.null(x$description)) cat(" ", x$description, "\n")
  cat(sprintf("  instructions: %d characters\n", nchar(x$instructions)))
  if (length(x$references)) {
    cat("  references:", paste(names(x$references), collapse = ", "), "\n")
  }
  if (length(x$scripts)) {
    cat("  scripts (never run here):", paste(names(x$scripts), collapse = ", "), "\n")
  }
  invisible(x)
}

#' The full path of a file in a skill folder, or an error when it resolves
#' to somewhere outside the folder (through a link).
#' @noRd
skill_inside <- function(root, rel, what) {
  f <- tryCatch(normalizePath(file.path(root, rel), winslash = "/", mustWork = TRUE),
                error = function(e) {
                  gr_abort(sprintf("%s: '%s' is a broken or looping link.", what, rel),
                           class = "hr_bad_skill")
                })
  if (!startsWith(f, paste0(root, "/"))) {
    gr_abort(sprintf("%s: '%s' is a link to a file outside the skill folder.", what, rel),
             class = "hr_bad_skill")
  }
  f
}

#' The files under one subfolder of a skill, as paths relative to the
#' folder, in a fixed order. Hidden files are left out. The subfolder must
#' resolve inside the skill folder, and a link to a folder under it is
#' refused, so the walk never leaves the skill folder and cannot loop. The
#' walk stops once it has found more files than are read.
#' @noRd
skill_files <- function(root, sub, what) {
  dir <- file.path(root, sub)
  if (!dir.exists(dir)) return(character(0))
  real <- tryCatch(normalizePath(dir, winslash = "/", mustWork = TRUE),
                   error = function(e) "")
  if (!startsWith(real, paste0(root, "/"))) {
    gr_abort(sprintf("%s: '%s/' is a link to a folder outside the skill folder.", what, sub),
             class = "hr_bad_skill")
  }
  rel <- character(0)
  todo <- ""
  while (length(todo)) {
    at <- todo[[1]]
    todo <- todo[-1]
    here <- if (nzchar(at)) file.path(dir, at) else dir
    entries <- list.files(here, no.. = TRUE)
    for (e in entries) {
      r <- if (nzchar(at)) paste0(at, "/", e) else e
      full <- file.path(dir, r)
      if (dir.exists(full)) {
        if (nzchar(Sys.readlink(full))) {
          gr_abort(sprintf(paste0("%s: '%s/%s' is a link to a folder; links to folders ",
                                  "are not followed."), what, sub, r),
                   class = "hr_bad_skill")
        }
        todo <- c(todo, r)
      } else {
        rel <- c(rel, r)
        if (length(rel) > .hr_skill_max_files) {
          gr_abort(sprintf("%s has at least %d files in %s/; at most %d are read.", what,
                           length(rel), sub, .hr_skill_max_files), class = "hr_bad_skill")
        }
      }
    }
  }
  # Names from the file system are marked UTF-8, so the radix sort accepts
  # non-ASCII names and the order is the same in every locale.
  rel <- sort(enc2utf8(rel), method = "radix")
  if (length(rel)) paste0(sub, "/", rel) else character(0)
}

#' The bytes of a skill file as UTF-8 text, or an error when they are not
#' text.
#' @noRd
skill_text <- function(bytes, rel, what) {
  if (any(bytes == as.raw(0L))) {
    gr_abort(sprintf("%s: '%s' has a nul byte, so it is not a text file.", what, rel),
             class = "hr_bad_skill")
  }
  x <- rawToChar(bytes)
  Encoding(x) <- "UTF-8"
  if (!validUTF8(x)) {
    gr_abort(sprintf("%s: '%s' is not UTF-8 text.", what, rel), class = "hr_bad_skill")
  }
  sub("^\ufeff", "", x)
}

#' The header and the instructions of a SKILL.md, read without a YAML
#' parser.
#' @noRd
skill_parse <- function(text, what) {
  lines <- sub("\r$", "", strsplit(text, "\n", fixed = TRUE)[[1]])
  if (!length(lines) || !identical(lines[[1]], "---")) {
    gr_abort(sprintf("%s: SKILL.md must start with a line that is exactly '---'.", what),
             class = "hr_bad_skill")
  }
  close <- which(lines == "---")
  close <- close[close > 1L]
  if (!length(close)) {
    gr_abort(sprintf("%s: the header of SKILL.md has no closing '---' line.", what),
             class = "hr_bad_skill")
  }
  close <- close[[1]]
  header <- list()
  for (line in lines[seq_len(close - 2L) + 1L]) {
    m <- regmatches(line, regexec("^([A-Za-z_][A-Za-z0-9_-]*):\\s*(.*)$", line))[[1]]
    if (!length(m)) {
      gr_abort(sprintf(paste0("%s: the header line '%s' is not `key: value`. The header is ",
                              "read without a YAML parser, so nested or indented values are ",
                              "not allowed."), what, line), class = "hr_bad_skill")
    }
    key <- m[[2]]
    value <- trimws(m[[3]])
    if (grepl("^[|>]", value)) {
      gr_abort(sprintf(paste0("%s: the header value of '%s' is spread over lines (`|` or ",
                              "`>`); write it on one line."), what, key),
               class = "hr_bad_skill")
    }
    if (key %in% names(header)) {
      gr_abort(sprintf("%s: the header names '%s' twice.", what, key), class = "hr_bad_skill")
    }
    if (nchar(value) >= 2L) {
      q <- substr(value, 1L, 1L)
      if (q %in% c("\"", "'") && identical(substr(value, nchar(value), nchar(value)), q)) {
        value <- substr(value, 2L, nchar(value) - 1L)
      }
    }
    header[[key]] <- value
  }
  unknown <- setdiff(names(header), .hr_skill_keys)
  if (length(unknown)) {
    gr_warn(sprintf("%s: the header %s %s, which hr_skill() does not read; %s ignored.",
                    what, if (length(unknown) == 1L) "key" else "keys",
                    paste0("'", unknown, "'", collapse = ", "),
                    if (length(unknown) == 1L) "it is" else "they are"),
            class = "hr_skill_unknown_key")
  }
  header <- header[intersect(.hr_skill_keys, names(header))]
  if (!is_bench_string(header$name)) {
    gr_abort(sprintf("%s: the header of SKILL.md needs a `name`.", what), class = "hr_bad_skill")
  }
  if (!is.null(header$version) && !nzchar(header$version)) header$version <- NULL
  if (!is.null(header$description) && !nzchar(header$description)) header$description <- NULL
  body <- lines[-seq_len(close)]
  instructions <- trimws(paste(body, collapse = "\n"))
  if (!nzchar(instructions)) {
    gr_abort(sprintf("%s: SKILL.md has no instructions after its header.", what),
             class = "hr_bad_skill")
  }
  list(header = header, instructions = instructions)
}

#' The system message a skill adds to a step's requests: the instructions,
#' then each reference under its path.
#' @noRd
skill_message <- function(skill) {
  refs <- skill$references
  parts <- c(skill$instructions,
             if (length(refs)) sprintf("Reference %s:\n%s", names(refs), trimws(refs)))
  list(role = "system", content = paste(parts, collapse = "\n\n"))
}

#' A step's context with a skill: `skill` set, and `call` and `call_json`
#' sending the skill's system message before the step's messages.
#' @noRd
skill_ctx <- function(ctx, skill) {
  ctx[["skill"]] <- skill
  msg <- skill_message(skill)
  call <- ctx[["call"]]
  if (is.function(call)) {
    ctx[["call"]] <- function(messages, ...) {
      call(c(list(msg), normalise_messages(messages)), ...)
    }
  }
  call_json <- ctx[["call_json"]]
  if (is.function(call_json)) {
    ctx[["call_json"]] <- function(messages, schema, ...) {
      call_json(c(list(msg), normalise_messages(messages)), schema, ...)
    }
  }
  ctx
}
