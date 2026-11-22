# test-boundary.R: the core layer does not call or read the document layer.
#
# R/ is split into core-*.R (the general core), doc-*.R (the document layer),
# compat-*.R (shims) and the glue files zzz.R and harnessr-package.R. No
# function defined in a core file may call a function defined in a doc file,
# or use a value defined in one (the document layer's state, a pattern, a
# table), except the crossings listed in fixtures/boundary/allowed.csv.
#
# The tests run against the installed package, where R/ is not available, so
# the layer of each object is read from fixtures/boundary/layers.csv. After
# adding, removing or moving an object, run `Rscript dev/record-layers.R`
# from the repository root to rewrite it. allowed.csv is edited by hand and
# should only shrink: when a crossing is removed, delete its row. The parsing
# is in helper-boundary.R.

test_that("every namespace object is placed in a layer", {
  layers <- boundary_layers()
  missing <- setdiff(boundary_ns_objects(), layers$name)
  expect(length(missing) == 0,
         sprintf(paste("Not in fixtures/boundary/layers.csv: %s.",
                       "Run Rscript dev/record-layers.R from the repository root."),
                 paste(missing, collapse = ", ")))
})

test_that("layers.csv names only objects that exist, as what they are", {
  layers <- boundary_layers()
  odd <- setdiff(layers$layer, c("core", "doc", "compat", "glue"))
  expect(length(odd) == 0, sprintf("Unknown layer in layers.csv: %s.",
                                   paste(odd, collapse = ", ")))
  gone <- setdiff(layers$name, boundary_ns_objects())
  expect(length(gone) == 0,
         sprintf(paste("In fixtures/boundary/layers.csv but not in the namespace: %s.",
                       "Run Rscript dev/record-layers.R from the repository root."),
                 paste(gone, collapse = ", ")))
  ns <- asNamespace("harnessr")
  here <- layers[layers$name %in% boundary_ns_objects(), ]
  is_fun <- vapply(here$name, function(n) is.function(get(n, envir = ns)), logical(1))
  wrong <- here$name[is_fun != (here$kind == "function")]
  expect(length(wrong) == 0,
         sprintf(paste("The kind in fixtures/boundary/layers.csv is out of date for: %s.",
                       "Run Rscript dev/record-layers.R from the repository root."),
                 paste(wrong, collapse = ", ")))
})

test_that("core functions call doc functions only where allowed", {
  skip_if_not_installed("codetools")
  found <- boundary_crossings(boundary_layers())
  found <- found[found$kind == "function", ]
  new <- setdiff(boundary_key(found), boundary_key(boundary_allowed()))
  expect(length(new) == 0,
         sprintf(paste("Core calls the document layer: %s.",
                       "Move the code, or list the pair in fixtures/boundary/allowed.csv",
                       "with the phase that removes it."),
                 paste(new, collapse = "; ")))
})

test_that("core functions use doc values only where allowed", {
  skip_if_not_installed("codetools")
  found <- boundary_crossings(boundary_layers())
  found <- found[found$kind != "function", ]
  new <- setdiff(boundary_key(found), boundary_key(boundary_allowed()))
  expect(length(new) == 0,
         sprintf(paste("Core reads or changes a document layer object: %s.",
                       "Keep what the core needs in hr_state or reach it through a hook,",
                       "or list the pair in fixtures/boundary/allowed.csv with the phase",
                       "that removes it."),
                 paste(new, collapse = "; ")))
})

test_that("every allowed crossing still occurs", {
  skip_if_not_installed("codetools")
  found <- boundary_crossings(boundary_layers())
  allowed <- boundary_allowed()
  expect_true(all(nzchar(trimws(allowed$reason))))
  stale <- setdiff(boundary_key(allowed), boundary_key(found))
  expect(length(stale) == 0,
         sprintf("No longer crosses, delete from fixtures/boundary/allowed.csv: %s.",
                 paste(stale, collapse = "; ")))
})
