# Task brief: UTF-8 locale in the ai-sandbox image

Date: 2026-10-02. Small task, no spec.

## Problem (confirmed)

The generated Dockerfile in `bin/ai/create-ai-sandbox.sh` sets no `LANG`.
Inside a sandbox `LANG` is unset and Java reports
`sun.jnu.encoding = ANSI_X3.4-1968`, so Java cannot open a file whose name has
non-ASCII characters. Reproduced on the host: a Gradle build failed with
`Failed to create MD5 hash for file: .../Kampus_Panorama-Wroc??aw-768x460.jpg
(No such file or directory)`; the same build with `-e LANG=C.UTF-8` no longer
fails that way. The `C.utf8` locale is already present in the image
(`locale -a`).

## Goal

Every process in the sandbox (interactive shells, `ai-sandbox <cmd>`,
`docker exec`, the entrypoint) runs with `LANG=C.UTF-8`.

## Tests

Regression test first, in the existing suite (`tests/ai-sandbox/`, most likely
`test-image.sh`, which asserts on the generated Dockerfile text): the
generated Dockerfile sets `LANG=C.UTF-8` in an `ENV` that applies to the final
image. Run the targeted test file, then the whole suite once
(`bash tests/ai-sandbox/run-tests.sh`).

## Acceptance

- The test fails before the change and passes after it; the full suite passes.
- No other behaviour changes. The image hash changes, so the shared image is
  rebuilt once on the next `create-ai-sandbox.sh`; that is expected.
- Do not commit; the lead commits after review.
