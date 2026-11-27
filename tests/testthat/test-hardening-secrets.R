# Credentials: hr_step_command() hides variables that look like credentials
# from the program it runs, and mask_secrets masks key-shaped strings in the
# copies harnessr stores and prints.

sec_rscript <- file.path(R.home("bin"), "Rscript")

# A step that prints the named variables, each as NAME=value, one a line.
sec_env_step <- function(vars) {
  code <- sprintf("for (v in c(%s)) cat(v, '=', Sys.getenv(v), '\\n', sep = '')",
                  paste0("'", vars, "'", collapse = ", "))
  hr_step_command("env", c(sec_rscript, "-e", code))
}

sec_seen <- function(out) {
  lines <- strsplit(out$check$stdout, "\n", fixed = TRUE)[[1]]
  vals <- sub("^[^=]*=", "", lines)
  stats::setNames(vals, sub("=.*$", "", lines))
}

test_that("a variable matching each pattern is hidden from the program, and put back", {
  vars <- c(HRT_SVC_API_KEY = "v-api-key-1", HRT_SVC_TOKEN = "v-token-2",
            HRT_SVC_SECRET = "v-secret-3", HRT_SVC_PASSWORD = "v-password-4",
            HRT_SVC_PAT = "v-pat-5", HRT_SVC_SECRET_ACCESS_KEY = "v-sak-6",
            hrt_lower_token = "v-lower-7", HRT_PLAIN = "plain-8")
  withr::local_envvar(vars)
  seen <- sec_seen(sec_env_step(names(vars))(list(), list()))
  expect_identical(unname(seen[setdiff(names(vars), "HRT_PLAIN")]), rep("", 7L))
  expect_identical(unname(seen["HRT_PLAIN"]), "plain-8")
  expect_identical(Sys.getenv("HRT_SVC_TOKEN"), "v-token-2")
  expect_identical(Sys.getenv("HRT_SVC_API_KEY"), "v-api-key-1")
})

test_that("the provider variables and api_headers values are hidden", {
  withr::local_envvar(c(GITHUB_PAT = "gh-pat-value", OPENAI_API_KEY = "sk-not-real",
                        HRT_GATEWAY = "gateway-secret-value"))
  old <- hr_options()
  on.exit(hr_options(old), add = TRUE)
  hr_options(api_headers = c("api-key" = Sys.getenv("HRT_GATEWAY")))
  seen <- sec_seen(sec_env_step(c("GITHUB_PAT", "OPENAI_API_KEY", "HRT_GATEWAY"))(list(), list()))
  expect_identical(unname(seen), c("", "", ""))
})

test_that("a short api_headers value hides no variable", {
  withr::local_envvar(c(HRT_FLAG = "true", HRT_TEAM = "finance", HRT_GW = "gateway-key-0123"))
  old <- hr_options()
  on.exit(hr_options(old), add = TRUE)
  hr_options(api_headers = c("X-Debug" = "true", "X-Team" = "finance",
                             "api-key" = "gateway-key-0123"))
  seen <- sec_seen(sec_env_step(c("HRT_FLAG", "HRT_TEAM", "HRT_GW"))(list(), list()))
  expect_identical(unname(seen), c("true", "finance", ""))
})

test_that("the variable behind options(harnessr.api_key) is hidden", {
  withr::local_envvar(c(HRT_LLM_KEY = "sk-live-0123456789abcdefghij", HRT_SHORT = "abc"))
  withr::local_options(harnessr.api_key = Sys.getenv("HRT_LLM_KEY"))
  seen <- sec_seen(sec_env_step(c("HRT_LLM_KEY", "HRT_SHORT"))(list(), list()))
  expect_identical(unname(seen), c("", "abc"))
  # A key shorter than 8 characters hides nothing.
  withr::local_options(harnessr.api_key = "abc")
  seen <- sec_seen(sec_env_step("HRT_SHORT")(list(), list()))
  expect_identical(unname(seen), "abc")
})

test_that("an api_headers value that is not valid UTF-8 does not stop a command step", {
  old <- hr_options()
  on.exit(hr_options(old), add = TRUE)
  bad <- rawToChar(as.raw(c(0xff, 0xfe, 0x41:0x47)))
  hr_options(api_headers = list(z = bad))
  out <- hr_step_command("echo", c(sec_rscript, "-e", "cat('hi')"))(list(), list())
  expect_identical(out$check$status, "passed")
  expect_identical(out$check$stdout, "hi")
})

test_that("a name the user adds is hidden, and the count is recorded", {
  withr::local_envvar(c(HRT_REGION = "eu-west", HRT_OTHER = "kept", HRT_X_TOKEN = "t-1"))
  old <- hr_options()
  on.exit(hr_options(old), add = TRUE)
  step <- sec_env_step(c("HRT_REGION", "HRT_OTHER"))
  tr <- hr_trace()
  out <- step(list(), list(trace = tr))
  expect_identical(unname(sec_seen(out)), c("eu-west", "kept"))
  before <- tr$steps[[1]]$detail$hidden_env
  hr_options(command_hide_env = "^hrt_region$")
  tr <- hr_trace()
  out <- step(list(), list(trace = tr))
  expect_identical(unname(sec_seen(out)), c("", "kept"))
  expect_identical(tr$steps[[1]]$detail$hidden_env, before + 1L)
  expect_identical(tr$steps[[1]]$detail$hidden_env, length(harnessr:::command_hidden_env()))
  # The count only: no name and no value reaches the trace.
  txt <- as.character(as_json(tr))
  expect_false(grepl("HRT_REGION", txt, fixed = TRUE))
  expect_false(grepl("eu-west", txt, fixed = TRUE))
  expect_null(out$check$hidden_env)
  expect_error(hr_options(command_hide_env = "("), class = "gr_bad_option")
  expect_error(hr_options(command_hide_env = NA_character_), class = "gr_bad_option")
})

test_that("command_temp_home gives the program an empty HOME and puts HOME back", {
  old <- hr_options()
  on.exit(hr_options(old), add = TRUE)
  home <- Sys.getenv("HOME")
  step <- hr_step_command("home", c(sec_rscript, "-e",
    "h <- Sys.getenv('HOME'); cat(h, length(list.files(h, all.files = TRUE, no.. = TRUE)), sep = '|')"))
  out <- step(list(), list())$check$stdout
  expect_identical(sub("\\|.*$", "", out), home)
  hr_options(command_temp_home = TRUE)
  out <- step(list(), list())$check$stdout
  parts <- strsplit(out, "|", fixed = TRUE)[[1]]
  expect_false(identical(parts[1], home))
  expect_identical(parts[2], "0")
  expect_false(dir.exists(parts[1]))
  expect_identical(Sys.getenv("HOME"), home)
})

# Planted keys of the common shapes, each built here so no file holds one.
sec_keys <- function() {
  c(openai = paste0("sk-proj-", strrep("a1B2", 12)),
    anthropic = paste0("sk-ant-api03-", strrep("Xy9_", 10)),
    github = paste0("ghp_", strrep("Ab3d", 9)),
    github_pat = paste0("github_pat_", strrep("11AbC", 6)),
    aws = paste0("AKIA", "IOSFODNN7EXAMPLE"),
    google = paste0("AIza", strrep("Sy9-", 8), "abc"),
    slack = paste0("xoxb-", "1234567890-abcdefghij"),
    hf = paste0("hf_", strrep("qWeR", 9)),
    jwt = paste0("eyJ", strrep("hbGciOi", 2), ".", strrep("eyJzdWIi", 2), ".",
                 strrep("SflKxwRJ", 2)),
    bearer = paste0("Bearer ", strrep("tOkEn.", 5)))
}

test_that("masking replaces planted keys of common shapes and leaves ordinary text alone", {
  keys <- sec_keys()
  for (nm in names(keys)) {
    m <- harnessr:::mask_secrets(paste("before", keys[[nm]], "after"))
    expect_identical(m$n, 1L, info = nm)
    expect_false(grepl(sub("^Bearer ", "", keys[[nm]]), m$text, fixed = TRUE), info = nm)
    expect_match(m$text, "^before .*<masked> after$", info = nm)
  }
  plain <- c("The task-management-system-overview has a risk-free path.",
             "Revenue was 45.2 million dollars in 2024; ask the AKIA team.",
             "sk-short and ghp_tiny and Bearer abc are not keys.",
             "eyJ alone is not a token, nor is hf_x.")
  m <- harnessr:::mask_secrets(plain)
  expect_identical(m$text, plain)
  expect_identical(m$n, 0L)
  # A hidden variable's value is masked wherever it appears.
  m <- harnessr:::mask_secrets("value=gateway-secret-value!", values = "gateway-secret-value")
  expect_identical(m$text, "value=<masked>!")
})

test_that("command output is masked only when asked, and the hash is of the output as printed", {
  old <- hr_options()
  on.exit(hr_options(old), add = TRUE)
  key <- sec_keys()[["openai"]]
  step <- hr_step_command("leak", c(sec_rscript, "-e",
    sprintf("cat('key %s here'); message('err %s')", key, key)))
  tr <- hr_trace()
  plain <- step(list(), list(trace = tr))$check
  expect_identical(plain$stdout, sprintf("key %s here", key))
  expect_null(tr$steps[[1]]$detail$masked)
  hash <- tr$steps[[1]]$detail$stdout_hash
  hr_options(mask_secrets = TRUE)
  tr <- hr_trace()
  masked <- step(list(), list(trace = tr))$check
  expect_identical(masked$stdout, "key <masked> here")
  expect_false(grepl(key, masked$stderr, fixed = TRUE))
  expect_identical(tr$steps[[1]]$detail$masked, 2L)
  expect_identical(tr$steps[[1]]$detail$stdout_hash, hash)
})

test_that("a saved trace and a printed trace are masked only when asked", {
  old <- hr_options()
  on.exit(hr_options(old), add = TRUE)
  key <- sec_keys()[["anthropic"]]
  cl <- hr_mock_client(function(m, p) stop(sprintf("Incorrect API key provided: %s", key)))
  tr <- hr_trace()
  hr_call(cl, sprintf("my key is %s", key), trace = tr)
  f <- tempfile(fileext = ".json")
  on.exit(unlink(f), add = TRUE)
  # Off: the file is as_json() byte for byte, and the print shows the text.
  hr_trace_save(tr, f)
  expect_identical(paste(readLines(f), collapse = "\n"), as.character(as_json(tr)))
  expect_true(any(grepl(key, capture.output(print(tr)), fixed = TRUE)))
  hr_options(mask_secrets = TRUE)
  hr_trace_save(tr, f)
  saved <- jsonlite::read_json(f)
  expect_false(any(grepl(key, readLines(f), fixed = TRUE)))
  expect_identical(saved$masked, 3L)
  expect_identical(saved$steps[[1]]$prompt[[1]]$content, "my key is <masked>")
  # The trace in the session, and the step's replay key, are as they were.
  expect_identical(tr$steps[[1]]$prompt[[1]]$content, sprintf("my key is %s", key))
  expect_identical(saved$steps[[1]]$replay_key, tr$steps[[1]]$replay_key)
  out <- capture.output(print(tr))
  expect_false(any(grepl(key, out, fixed = TRUE)))
  expect_true(any(grepl("^  masked: 1 key-shaped string\\(s\\)$", out)))
})

test_that("masking changes no cache or replay key", {
  old <- hr_options()
  on.exit(hr_options(old), add = TRUE)
  key <- sec_keys()[["github"]]
  cl <- hr_mock_client(function(m, p) "an answer")
  a <- hr_trace()
  hr_call(cl, sprintf("token %s", key), trace = a)
  hr_options(mask_secrets = TRUE)
  b <- hr_trace()
  hr_call(cl, sprintf("token %s", key), trace = b)
  expect_identical(a$steps[[1]]$replay_key, b$steps[[1]]$replay_key)
  expect_identical(a$steps[[1]]$prompt, b$steps[[1]]$prompt)
  # A replay of the masked file finds its reply by the recorded key.
  f <- tempfile(fileext = ".json")
  on.exit(unlink(f), add = TRUE)
  hr_trace_save(b, f)
  rp <- hr_replay_client(f)
  expect_identical(hr_call(rp, sprintf("token %s", key))$text, "an answer")
})
