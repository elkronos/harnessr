# core-registry-schema.R: parameter schemas, cost declarations, and specs turned
# into plain lists of settings.

#' Normalise a list of named specs coming from a user (recipe fields).
#' @noRd
as_spec_list <- function(x, what = "spec") {
  if (is.null(x)) return(list())
  if (is.character(x) && length(x) == 1L) return(list(method = x))
  if (!is.list(x)) gr_abort(sprintf("`%s` must be a string or a named list, got <%s>.", what, class(x)[1]))
  x
}

# NOTE: there is deliberately no `str()` shim here. Defining one would shadow
# `utils::str` for every function in this package to save one qualified call in
# `gr_hash()`, which calls `utils::str()` directly instead.


#' The settings of a spec that differ from its defaults.
#'
#' A trace used to record the recipe's NAME and nothing else about how it was
#' configured, so two runs of `"thorough"` with `top_k = 3` and `top_k = 8`
#' produced traces -- and a `gr_compare()` summary -- that could not be told
#' apart. For a package whose point is comparing configurations, the
#' configuration has to be in the record. This returns only what was changed
#' from the defaults, so the record says what the run DID rather than restating
#' thirty defaults; `format_settings()` makes it one readable string.
#'
#' Defaults are taken from the constructor at the time of the call, so a
#' `model` or `parallel` that merely follows `gr_options()` is not reported as
#' a setting.
#' @noRd
spec_settings <- function(spec, defaults, drop = character(0)) {
  same <- function(a, b) isTRUE(all.equal(a, b, check.attributes = FALSE))
  out <- list()
  for (nm in setdiff(names(spec), drop)) {
    v <- spec[[nm]]
    if (is.null(v) || is.function(v) || is.environment(v)) next
    if (nm %in% names(defaults) && same(v, defaults[[nm]])) next
    out[[nm]] <- v
  }
  out
}

#' One line, for a summary column: `top_k=3, mmr=0.7`.
#' @noRd
format_settings <- function(x) {
  if (!length(x)) return("")
  paste(vapply(names(x), function(nm) {
    v <- x[[nm]]
    # A named vector keeps its names: an effort map printed as "low+high"
    # would not say which stage ran at which.
    val <- if (is.character(v) && !is.null(names(v)) && any(nzchar(names(v))))
             paste(ifelse(nzchar(names(v)), paste0(names(v), ":", v), v), collapse = "+")
           else if (is.character(v)) paste(v, collapse = "+")
           else if (is.logical(v) || is.numeric(v)) paste(format(v, trim = TRUE), collapse = "+")
           else class(v)[1]
    paste0(nm, "=", val)
  }, character(1)), collapse = ", ")
}

# Parameter schemas.
#
# Each spec constructor used to check its own arguments: a clamp here, an NA
# fallback there, a match.arg() for the choices, each with its own range
# written inline and repeated in the help page. A schema states every
# parameter once (its type, default, range and choices) and hr_validate()
# applies the same rules to all of them, so a range is changed in one place
# and a later UI or command line can be built from the same list.

.hr_cost_classes <- c("none", "local", "per_call_constant", "per_unit", "per_sample",
                      "per_round")

#' Declare one parameter of a module or spec
#'
#' A parameter states its type, default and allowed values once, so that the
#' spec it belongs to is validated the same way wherever it is built.
#' [hr_validate()] applies the rules; [hr_schema()] collects parameters into
#' a schema.
#'
#' The rules by type:
#' \describe{
#'   \item{`integer`, `number`}{A value that is missing, not a single value or
#'     not a number falls back to `default`, with a `gr_bad_setting` warning.
#'     With `min` or `max`, a value outside the range is moved to the nearest
#'     bound and warned about (`gr_clamped`, also of class `hr_param_clamped`).
#'     An `integer` comes back as an integer.}
#'   \item{`boolean`}{With `strict = TRUE`, anything but a single `TRUE` or
#'     `FALSE` is an error (`gr_bad_setting`). With `strict = FALSE`, anything
#'     but `TRUE` is read as `FALSE`.}
#'   \item{`enum`}{One of `choices`, matched as [match.arg()] matches, so an
#'     unambiguous abbreviation is accepted and the whole `choices` vector
#'     means the first choice. Anything else is an error naming the choices.}
#'   \item{`string`, `file`, `module_ref`}{A single non-blank string, or
#'     `NULL` when the default is `NULL`.}
#'   \item{`string_vector`}{A character vector, or `NULL` when the default
#'     is `NULL`.}
#'   \item{`named_map`}{A character vector, or a list whose elements all have
#'     non-empty names (an empty list is one), or `NULL` when the default is
#'     `NULL`.}
#' }
#' A `resolve` function replaces the type's rule for a parameter that needs
#' its own, such as an effort map checked against declared call stems.
#'
#' @param name The parameter's name, as the spec field it fills.
#' @param type One of `"integer"`, `"number"`, `"string"`, `"boolean"`,
#'   `"enum"`, `"string_vector"`, `"named_map"`, `"module_ref"` or `"file"`.
#' @param default The value used when none is given.
#' @param min,max Bounds for `integer` and `number`. Either may be a function
#'   of the parameters resolved before this one, for a bound that depends on
#'   another setting.
#' @param choices The allowed values of an `enum`.
#' @param required Whether a value must be given.
#' @param help One plain sentence saying what the parameter does.
#' @param cost_class How the parameter moves the cost of a run: `"none"`,
#'   `"local"`, `"per_call_constant"`, `"per_unit"`, `"per_sample"` or
#'   `"per_round"`.
#' @param affects_output Whether the parameter can change what a run returns,
#'   and so belongs in cache and store keys.
#' @param tier `"basic"` or `"advanced"`, for grouping in a user interface.
#' @param evidence `NULL`, or a list saying where the setting comes from and
#'   whether its benefit has been measured.
#' @param depends_on `NULL`, or a condition (a string) under which the
#'   parameter applies.
#' @param since The version that added the parameter.
#' @param kind For `module_ref`: the kind of module it names.
#' @param strict For `boolean`: whether a value other than `TRUE` or `FALSE`
#'   is an error rather than `FALSE`.
#' @param resolve `NULL`, or a function of `(value, param, params)` returning
#'   the resolved value, used instead of the type's rule. `params` holds the
#'   parameters resolved before this one.
#' @return An object of class `hr_param`.
#' @seealso [hr_schema()], [hr_validate()]
#' @export
#' @examples
#' p <- hr_param("top_k", "integer", default = 6L, min = 1, max = 1e4,
#'               help = "Chunks to use.")
#' hr_validate(hr_schema(p), list(top_k = 8))$top_k
#'
#' # Out of range: moved to the bound and warned about.
#' suppressWarnings(hr_validate(hr_schema(p), list(top_k = 0))$top_k)
hr_param <- function(name, type = c("integer", "number", "string", "boolean", "enum",
                                    "string_vector", "named_map", "module_ref", "file"),
                     default = NULL, min = NULL, max = NULL,
                     choices = NULL, required = FALSE, help = "", cost_class = "none",
                     affects_output = TRUE, tier = c("basic", "advanced"), evidence = NULL,
                     depends_on = NULL, since = NULL, kind = NULL, strict = TRUE,
                     resolve = NULL) {
  if (!is_nonblank(name)) gr_abort("A parameter's `name` must be a non-empty string.",
                                   class = "gr_bad_setting")
  # match.arg() alone stops with a bare "'arg' should be one of", which names
  # neither the parameter nor the argument.
  one_of <- function(x, arg) {
    allowed <- eval(formals(hr_param)[[arg]])
    tryCatch(match.arg(x, allowed), error = function(e) {
      gr_abort(sprintf("`%s` of '%s' must be one of %s.", arg, name,
                       paste(allowed, collapse = ", ")), class = "gr_bad_setting")
    })
  }
  type <- one_of(type, "type")
  tier <- one_of(tier, "tier")
  if (!cost_class %in% .hr_cost_classes) {
    gr_abort(sprintf("`cost_class` of '%s' must be one of %s.", name,
                     paste(.hr_cost_classes, collapse = ", ")), class = "gr_bad_setting")
  }
  if (identical(type, "enum") && (!is.character(choices) || !length(choices))) {
    gr_abort(sprintf("The enum parameter '%s' needs `choices`.", name), class = "gr_bad_setting")
  }
  bound_ok <- function(b) is.null(b) || is.function(b) || (is.numeric(b) && length(b) == 1L)
  if (!bound_ok(min) || !bound_ok(max)) {
    gr_abort(sprintf("`min` and `max` of '%s' must be single numbers or functions.", name),
             class = "gr_bad_setting")
  }
  if (!is.null(resolve) && !is.function(resolve)) {
    gr_abort(sprintf("`resolve` of '%s' must be a function.", name), class = "gr_bad_setting")
  }
  structure(list(name = name, type = type, default = default, min = min, max = max,
                 choices = choices, required = isTRUE(required), help = help,
                 cost_class = cost_class, affects_output = isTRUE(affects_output), tier = tier,
                 evidence = evidence, depends_on = depends_on, since = since, kind = kind,
                 strict = isTRUE(strict), resolve = resolve),
            class = "hr_param")
}

#' Collect parameters into a schema
#'
#' @param ... [hr_param()] objects. Their order is the order [hr_validate()]
#'   resolves them in, so a bound that depends on another parameter comes
#'   after it.
#' @return An object of class `hr_schema`: a list of `hr_param`, named by
#'   parameter.
#' @seealso [hr_param()], [hr_validate()]
#' @export
#' @examples
#' s <- hr_schema(
#'   hr_param("max_tokens", "integer", default = 1200L, min = 32, max = 1e6),
#'   hr_param("overlap_tokens", "integer", default = 0L, min = 0,
#'            max = function(p) p$max_tokens - 1L))
#' suppressWarnings(hr_validate(s, list(max_tokens = 100, overlap_tokens = 500)))
hr_schema <- function(...) {
  params <- list(...)
  if (!all(vapply(params, inherits, logical(1), "hr_param"))) {
    gr_abort("Every argument of hr_schema() must come from hr_param().", class = "gr_bad_setting")
  }
  nms <- vapply(params, `[[`, character(1), "name")
  dup <- unique(nms[duplicated(nms)])
  if (length(dup)) {
    gr_abort(sprintf("A schema names %s more than once.", paste0("'", dup, "'", collapse = ", ")),
             class = "gr_bad_setting")
  }
  structure(stats::setNames(params, nms), class = "hr_schema")
}

#' @export
print.hr_schema <- function(x, ...) {
  cat(sprintf("<hr_schema> %d parameter(s)\n", length(x)))
  for (p in x) {
    range <- if (!is.null(p$choices)) paste(p$choices, collapse = "|")
             else if (!is.null(p$min) || !is.null(p$max)) {
               b <- function(v, d) if (is.null(v)) d else if (is.function(v)) "f()" else format(v)
               sprintf("[%s, %s]", b(p$min, "-Inf"), b(p$max, "Inf"))
             } else ""
    cat(sprintf("  %-26s %-13s %s\n", p$name, p$type, range))
  }
  invisible(x)
}

#' Validate and resolve settings against a schema
#'
#' Applies each parameter's rule (see [hr_param()]) to the value given for it,
#' or to its default when none is given, in schema order.
#'
#' @param schema An [hr_schema()].
#' @param values A named list of settings. A name the schema does not have is
#'   an error of class `hr_unknown_param`.
#' @return A named list with one resolved value per parameter, in schema
#'   order. A parameter that resolves to `NULL` is kept as a `NULL` element.
#' @seealso [hr_param()], [hr_schema()]
#' @export
#' @examples
#' s <- hr_schema(hr_param("order", "enum", choices = c("relevance", "document")))
#' hr_validate(s, list(order = "doc"))$order
hr_validate <- function(schema, values = list()) {
  if (!inherits(schema, "hr_schema")) gr_abort("`schema` must come from hr_schema().",
                                               class = "gr_bad_setting")
  if (is.null(values)) values <- list()
  if (!is.list(values)) gr_abort("`values` must be a named list.", class = "gr_bad_setting")
  given <- names(values) %||% rep("", length(values))
  unknown <- setdiff(given, names(schema))
  if (length(unknown)) {
    gr_abort(sprintf("%s not a parameter of this schema. Parameters: %s.",
                     paste0("'", unknown, "'", collapse = ", "),
                     paste(names(schema), collapse = ", ")),
             class = c("hr_unknown_param", "gr_bad_setting"))
  }
  out <- list()
  for (p in schema) {
    x <- if (p$name %in% given) values[[p$name]] else p$default
    if (is.null(x) && p$required) {
      gr_abort(sprintf("`%s` is required.", p$name), class = "gr_bad_setting")
    }
    v <- if (is.function(p$resolve)) p$resolve(x, p, out) else param_resolve(x, p, out)
    # `out[[name]] <- NULL` would drop the element; a NULL setting is kept.
    out[p$name] <- list(v)
  }
  out
}

#' The rule of a parameter's type, applied to one value.
#' @noRd
param_resolve <- function(x, p, params) {
  name <- p$name
  bound <- function(b, d) if (is.null(b)) d else if (is.function(b)) b(params) else b
  switch(p$type,
    integer = , number = {
      x <- na_default(x, p$default, name)
      if (is.null(p$min) && is.null(p$max)) {
        if (identical(p$type, "integer")) as_int1(x, p$default) else x
      } else {
        clamp_warn(x, bound(p$min, -Inf), bound(p$max, Inf), name,
                   integer = identical(p$type, "integer"),
                   class = c("gr_clamped", "hr_param_clamped"))
      }
    },
    boolean = {
      if (!p$strict) return(isTRUE(x))
      if (!is.logical(x) || length(x) != 1L || is.na(x)) {
        gr_abort(sprintf("`%s` must be TRUE or FALSE.", name), class = "gr_bad_setting")
      }
      x
    },
    enum = tryCatch(match.arg(x, p$choices), error = function(e) {
      gr_abort(sprintf("`%s` must be one of %s.", name,
                       paste0("\"", p$choices, "\"", collapse = ", ")),
               class = "gr_bad_setting")
    }),
    string = , file = , module_ref = {
      if (is.null(x) && is.null(p$default)) return(NULL)
      if (!is_nonblank(x)) gr_abort(sprintf("`%s` must be a non-empty string.", name),
                                    class = "gr_bad_setting")
      x
    },
    string_vector = {
      if (is.null(x) && is.null(p$default)) return(NULL)
      if (!is.character(x)) gr_abort(sprintf("`%s` must be a character vector.", name),
                                     class = "gr_bad_setting")
      x
    },
    named_map = {
      if (is.null(x) && is.null(p$default)) return(NULL)
      named <- is.list(x) && (!length(x) || (!is.null(names(x)) &&
                                               all(!is.na(names(x)) & nzchar(names(x)))))
      if (!is.character(x) && !named) {
        gr_abort(sprintf("`%s` must be a character vector or a list with every element named.",
                         name), class = "gr_bad_setting")
      }
      x
    })
}

#' A parameter rule that keeps the value as given, for settings a spec stores
#' without checking (a model name, a client option it passes on).
#' @noRd
param_as_given <- function(x, p, params) x

# Cost declarations.
#
# A reader used to state its cost as a display string ("N + merges"), and the
# pre-flight check repeated each built-in reader's call pattern by hand, so a
# registered reader was counted as one call per chunk whatever it did. A
# reader now states its cost as a function returning hr_cost(), and the
# pre-flight check adds those up.

#' What one run of a module can cost
#'
#' The return value of a module's `cost(input_stats, params)` function. Counts
#' are upper bounds for one run over the given input, except `calls`, which is
#' the number of model requests expected.
#'
#' @param calls Model requests the run is expected to make.
#' @param calls_max Model requests it can make at worst. Never taken as less
#'   than `calls` once costs are summed.
#' @param tokens_in_max Prompt tokens the run sends beyond the input itself
#'   and the fixed prompt of each request: replies handed on to later merge
#'   or summary requests.
#' @param tokens_out_max Reply tokens the run can be billed for at worst.
#'   Zero leaves it to the pre-flight check, which prices every request at
#'   `input_stats$out_cap`, the largest reply cap the run's model is sent. A
#'   module whose replies can exceed that states its own bound here, and the
#'   check uses the larger of the two.
#' @param embed_max Requests to the embeddings endpoint.
#' @param sends Input every run must send, as a list of `list(tokens =,
#'   model =)`: a reader that sends every chunk sends at least their tokens
#'   to the model that reads them. Priced to refuse a run that cannot finish
#'   under the spending limit before it starts. `NULL` is the same as none.
#' @param batched Whether requests can go out in parallel batches, which
#'   cannot be stopped part way and so are held to their worst case.
#' @return An object of class `hr_cost`.
#' @seealso [gr_register_reader()]
#' @export
#' @examples
#' hr_cost(calls = 4, calls_max = 6)
hr_cost <- function(calls, calls_max = calls, tokens_in_max = 0, tokens_out_max = 0,
                    embed_max = 0, sends = list(), batched = TRUE) {
  num <- function(v, what) {
    v <- suppressWarnings(as.numeric(v))
    if (length(v) != 1L || is.na(v) || v < 0) {
      gr_abort(sprintf("`%s` of a cost must be a single number, zero or more.", what),
               class = "gr_bad_setting")
    }
    v
  }
  if (is.null(sends)) sends <- list()
  if (!is.list(sends) || !all(vapply(sends, function(s) is.list(s) && !is.null(s$tokens),
                                     logical(1)))) {
    gr_abort("`sends` of a cost must be a list of list(tokens =, model =).",
             class = "gr_bad_setting")
  }
  structure(list(calls = num(calls, "calls"), calls_max = num(calls_max, "calls_max"),
                 tokens_in_max = num(tokens_in_max, "tokens_in_max"),
                 tokens_out_max = num(tokens_out_max, "tokens_out_max"),
                 embed_max = num(embed_max, "embed_max"), sends = sends,
                 batched = isTRUE(batched)),
            class = "hr_cost")
}

#' The total of several costs: counts added, `sends` joined, batched when any
#' part is. `extra_calls` adds requests made around the parts (an ensemble's
#' adjudication) to both the expected and the worst count.
#' @noRd
cost_sum <- function(parts, extra_calls = 0) {
  add <- function(field) sum(vapply(parts, function(p) as.numeric(p[[field]] %||% 0), numeric(1)))
  hr_cost(calls = extra_calls + add("calls"), calls_max = extra_calls + add("calls_max"),
          tokens_in_max = add("tokens_in_max"), tokens_out_max = add("tokens_out_max"),
          embed_max = add("embed_max"),
          sends = do.call(c, c(list(list()), lapply(parts, `[[`, "sends"))),
          batched = any(vapply(parts, function(p) isTRUE(p$batched), logical(1))))
}
