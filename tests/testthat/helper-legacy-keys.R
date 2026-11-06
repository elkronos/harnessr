# helper-legacy-keys.R: the calls behind fixtures/legacy-0.6.0/.
#
# The fixture holds a response cache and a strict-replay recording written by
# the code before the key change (commit c91b04b, cache key readgpt-cache-v2
# under xxhash64, replay key readgpt-replay-v1). dev/record-legacy-keys.R runs
# legacy_keys_calls() under that build to write them; test-compat-legacy-keys.R runs
# the same calls under this one and checks every one is answered through the
# old keys. Both must make exactly the same calls, so they share this file.
# It uses only functions that both builds have.

legacy_keys_dir <- function(root = NULL) {
  if (!is.null(root)) return(file.path(root, "tests", "testthat", "fixtures", "legacy-0.6.0"))
  testthat::test_path("fixtures", "legacy-0.6.0")
}

# The handler is not part of any key, but the replies are compared, so it is
# fixed. A schema call gets JSON that parses against the schema used below.
legacy_keys_handler <- function(messages, params) {
  if (!is.null(params$schema)) return("{\"revenue\": 45.2}")
  last <- messages[[length(messages)]]$content
  sprintf("Reply to %d characters at %s, effort %s.", nchar(last, type = "chars"),
          if (is.null(params$temperature)) "default temperature" else params$temperature,
          if (is.null(params$effort)) "none" else params$effort)
}

# A backend client with a fixed id: the id is part of the cache key, and a
# mock client draws a new one every time it is built.
legacy_keys_client <- function() {
  harnessr::gr_backend_client(legacy_keys_handler, model = "gpt-4o-mini",
                              id = "legacy-keys-fixture")
}

# The calls, in order. Defaults, a system message with a temperature and a cap,
# a schema, a reasoning model at an effort, non-ASCII text, and one prompt
# asked twice.
legacy_keys_calls <- function(cl, trace = NULL) {
  call <- function(...) harnessr::gr_call(cl, ..., trace = trace)
  list(
    call("What was revenue in 2024?"),
    call(list(list(role = "system", content = "Answer in one sentence."),
              list(role = "user", content = "Summarise the outlook.")),
         temperature = 0.3, max_output = 200),
    harnessr:::gr_call_json(cl, "Give revenue as JSON.",
                            schema = list(type = "object",
                                          properties = list(revenue = list(type = "number"))),
                            trace = trace),
    call("Weigh the risks.", model = "gpt-5-mini", effort = "low"),
    call("Caf\u00e9 revenue in \u20ac?"),
    call("What was revenue in 2024?")
  )
}
