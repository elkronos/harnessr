# How model_call() hands a prepared request to each kind of client.
# The dispatch methods are registered in NAMESPACE but not exported, so the
# tests reach the generics with harnessr:::.

test_that("the mock and the backend client send through one method", {
  expect_identical(harnessr:::client_send.gr_mock_client,
                   harnessr:::client_send.gr_backend_client)
  handler <- function(m, p) paste("reply to", m[[1]]$content)
  mock <- hr_mock_client(handler)
  back <- hr_backend_client(handler, model = "mock-model")
  a <- hr_call(mock, "hi", label = "one")
  b <- hr_call(back, "hi", label = "one")
  expect_identical(unclass(a), unclass(b))
  la <- mock$calls()[[1]]
  lb <- back$calls()[[1]]
  expect_identical(names(la), c("messages", "params", "result", "label"))
  expect_identical(la, lb)
})

test_that("each client class finds its own dispatch method", {
  find <- function(generic, cl) {
    for (k in class(cl)) {
      f <- utils::getS3method(generic, k, optional = TRUE, envir = asNamespace("harnessr"))
      if (!is.null(f)) return(k)
    }
    NA_character_
  }
  mock <- hr_mock_client(function(m, p) "ok")
  back <- hr_backend_client(function(m, p) "ok")
  ellm <- back
  class(ellm) <- c("gr_ellmer_client", class(ellm))
  expect_identical(find("client_dispatch", mock), "gr_client")
  expect_identical(find("client_send", mock), "gr_mock_client")
  expect_identical(find("client_send", back), "gr_backend_client")
  expect_identical(find("client_send", ellm), "gr_backend_client")
  expect_true(harnessr:::client_sends_effort(mock))
  expect_false(harnessr:::client_sends_effort(ellm))
})

test_that("a cache sits in front of a closure client and a replay never sends", {
  n <- 0
  cl <- hr_cache_client(hr_mock_client(function(m, p) { n <<- n + 1; "42" }),
                        hr_cache(tempfile("dispatch-cache")))
  tr <- hr_trace()
  first <- hr_call(cl, "what?", trace = tr)
  second <- hr_call(cl, "what?")
  expect_identical(n, 1)
  expect_false(first$cached)
  expect_true(second$cached)

  f <- tempfile(fileext = ".json")
  hr_trace_save(tr, f)
  rp <- hr_replay_client(f)
  expect_identical(hr_call(rp, "what?")$text, "42")
  expect_identical(n, 1)
})
