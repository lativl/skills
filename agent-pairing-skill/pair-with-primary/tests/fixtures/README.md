# Participant fixtures

Two directories holding **byte-identical** receipts. The only difference is whether the receipt is
committed, which is the single distinction the participant manual turns on.

`tests/run-tests.sh` materializes each as a Git repository — committing everything for
`committed-receipt/`, and everything *except* `turns/` for `uncommitted-receipt/` — then runs the
manual's own probe against both. A probe that answers "go" for the uncommitted one would start a turn
against work nobody authorized, which is the v1 defect this protocol exists to remove.
