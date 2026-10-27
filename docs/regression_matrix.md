# In-game regression observations

| Snapshot | Status | Evidence |
|---|---|---|
| global-recommended-debug | UNTESTED | Recommended next test; do not call it LKG |
| runtime-diagnostics | UNVERIFIED | Contains county diagnostics; not a proven clean baseline |
| hybrid-resource / isolation A | BAD | One-click global recommendation stalls, CCO context-read failure at Yizhou island capital |
| isolation B | BAD | Deferred request starts and issues commands, then fails at Jianye salt resource county |
| session-refactor | MIXED | Per-load automation resets off, but UI reopen issue |
| ui-phase-lock | BAD | Force run triggers bridge circuit and UI lock |

Only label `known-good` after actual in-game validation, using a reproducible save.
