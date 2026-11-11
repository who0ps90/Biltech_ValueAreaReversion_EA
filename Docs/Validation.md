# Validation checklist and evidence

## Recorded environment and results

Evidence date: **2026-10-25**. Files were created in the supplied Windows workspace. MetaEditor at `C:\Program Files\XM Global MT5\MetaEditor64.exe`, file/product version **5.0.0.6281**, compiled the EA and native test suite. Compiler output and generated `.ex5` files are retained. No broker account was connected and no trades were placed during development.

| Check | Recorded result | What it establishes |
|---|---|---|
| Python log-analysis tests | **PASS: 5 synthetic tests** | Signed costs, net statistics, R, New York exit-month grouping, directions, loss streak, duplicate-position rejection, DEAL exclusion, mixed ownership rejection, undefined profit factor |
| Structural package verifier | **PASS: 12 MQL source scans, 37 parsed inputs, 3 preset input-name checks** | Deliverable presence, delimiter/include scan, preset input-name agreement; never language compilation |
| Independent calendar model | **PASS: 815,232 NY + 815,232 EU hourly offsets; 23,064 broker gap/fold checks; 372 NY session checks, 2007–2099** | Host calendar-model checks only; [retained output](../Tests/calendar_model_results.txt); never MQL execution |
| MetaEditor EA compilation | **PASS: 0 errors, 0 warnings** | Actual MQL compiler accepted the source; [main compiler log](../Tests/compile_main.log) |
| MetaEditor native test compilation | **PASS: 0 errors, 0 warnings** | Actual MQL compiler accepted the test suite; [test compiler log](../Tests/compile_selftest.log) |
| Native `BVSelfTest` execution | **NOT PERFORMED: 171 assertions compiled only** | 39 core + 40 clock + 43 execution-helper + 49 journal assertions; no runtime pass claimed |
| Broker contract, margin, stops and fill execution | **NOT PERFORMED** | Requires actual MT5 symbol/account environment |
| Visual/nonvisual comparison | **NOT PERFORMED** | Requires same inputs, broker data and interval in MT5 |
| Historical baseline and out-of-sample backtest | **NOT PERFORMED** | No strategy expectancy/performance measured |
| Demo forward test | **NOT PERFORMED** | This build intentionally rejects non-tester operation |

The test fixtures are hand-designed checks, not market data. None of the host tests compile or run the MQL implementation. Passing packaging checks does not establish order correctness or profitable trading.

No verified broker historical timezone mapping, broker spread threshold or selected test dates/data experiment were supplied for a reproducible strategy run. These affect correctness and cannot be inferred from market names. MT5 was not launched or connected to a brokerage account, so the separate native fixture EA was also not executed. Its fixtures do not require the strategy's broker configuration. The strategy presets intentionally require clock/spread configuration before initialization.

## Host checks

From the project root with Python 3:

```powershell
python Tests/verify_source.py
python -m unittest discover -s Tests -p test_analyze_logs.py -v
```

The source verifier exits nonzero on missing files, unmatched delimiters, missing local quoted includes, external requests/imports, absent main handler/tester marker, or malformed/unknown/duplicate preset inputs. This shallow scan cannot resolve MQL types, overloads or event semantics, and cannot prove absence of future-data use or correct risk recovery. Actual compiler and runtime validation remain required.

For the independent Windows calendar oracle:

```powershell
powershell -NoProfile -File Tests/VerifyTimeMapping.ps1
```

This compares a host reconstruction of supported DST rules against Windows timezone data and tests gap/fold/session arithmetic. It does not invoke `BVTime.mqh`. Preserve its exact output with the Windows timezone-database version if used as evidence.

## Native deterministic tests

Compile `Tests/BVSelfTest.mq5` in MetaEditor, then run it as an EA in the local Strategy Tester. No trading requests are made by this test EA. Retain compiler diagnostics and Tester journal; require zero failures. Tests share the actual profile, state-machine and clock implementation with the strategy EA, so they validate those functions when genuinely run in MQL.

The suites cover deterministic profile allocation/conservation, tick-aligned edges and exact ties; source consistency, missing/zero volume and M1 coverage; mirrored setup/reclaim rules, deadline, invalidation and duplicate closed candles; session boundaries, DST gaps/folds, broker rules and supported years. Pure execution-helper fixtures cover volume rounding/caps/minimum risk, executable quote/spread/protection constraints and filling-policy selection. Journal fixtures cover hash membership, CSV escaping/partial-row rejection, sandbox writes/reloads, outbox payload preservation and future-dated state refusal. Temporary fixture files use a unique self-test prefix in the Tester sandbox and are cleaned up. Inspect `BVCoreTests.mqh`, `BVTimeTests.mqh`, `BVExecutionTests.mqh` and `BVJournalTests.mqh` for precise scope. The execution fixtures supply monetary loss per lot; they do not validate `OrderCalcProfit`, conversion rates, actual margin, `OrderCheck` or broker execution. Real execution and full EA state recovery need the integration cases below.

## Required integration checklist

Record actual outcome, run ID, timestamp and evidence for each case. An unchecked case is unverified.

| Case | Acceptance criterion | Evidence to retain |
|---|---|---|
| Prior-session/no future bars | Every profile M1 bar lies within the immediately preceding completed session; current-session bars never change frozen levels | Profile/source logs, chart, independently sampled M1 bars |
| Visual/nonvisual parity | Same levels, setup events and filled trades with identical data/inputs | Both CSV sets and reports |
| Coverage, empty/zero/holiday | Invalid sessions skipped with explicit reason; no substitution with older session | Signal/profile rejection rows |
| AUTO/REAL volume | No barwise source mixing; fallback visible; later missing real volume blocks remaining session | Profile source annotations and missing-source case |
| Symmetry and reclaim timing | Long/short mirror; bar five can confirm, bar six cannot; breakout never counts as weakening | Native fixtures and inspected chart examples |
| Session reset | No pending setup/entry crosses its profile-session boundary | Boundary event rows |
| DST and broker changes | Correct UTC/NY/session boundaries; ambiguous/missing mapping rejected; 23/25-hour sessions behave explicitly | Clock self-tests plus real broker data on transitions |
| First next-bar tick | One opportunity only; stale delayed/backlog confirms cannot enter; every entry still in window | Tick timestamps, signal and deal rows |
| Order duplicate suppression | Same event/restart produces no repeated order; failed attempt is not retried | Journal before/after restart, deal history |
| Contract sizing | Different gold/index tick/contract specifications yield account-currency SL risk no greater than budget after round down | Symbol specs, `OrderCalcProfit` plan, actual fills |
| Minimum lot | If minimum-lot loss plus allowance exceeds budget, reject rather than round up | Rejected plan and calculation |
| Spread/stops/target | Over-threshold points, too-close protection and target wrong side reject without moving target | Quote/spec/plan/rejection row |
| Margin/filling/protection | Failed margin/order check rejects; supported filling chosen; every actual fill has protective SL/TP | Order check result, transaction/history, position fields |
| Slippage/partial fills | Actual fill risk and actual deal accounting reconcile; unexpected exposure/protection failures trigger conservative management | Request/result, all fill rows, journal |
| New York daily loss | EA net plus floating threshold locks entries and requests only owned positions closed; next NY day baseline explicit | Equity/day journal, history, quotes and exit rows |
| Restart loss lockout | Same run ID/journal/history preserves locked day, day baseline and used directions; missing recovery evidence fails closed | Before/after initialization logs and deal history |
| Restart continuity | Rewound time, account/configuration mismatch, missing recorded entry deal or orphaned audit files refuse continuation | Deliberately isolated fixture copies and initialization diagnostics |
| First partial day | Default starts locked; explicit initial equity is used only when intentionally supplied | Initial-day journal, inputs |
| Forced exit over closure | Due 15:55 NY exit stays pending across no-tick/closed period and executes at next tradable opportunity | Cutoff, next tick and actual deal time |
| Hedging ownership | Only this symbol/magic's positions managed; foreign/manual positions untouched | Account position list before/after |
| Netting ownership | Foreign or mixed ownership blocks entry/management that would interfere | Conflict rejection and deal ownership trace |
| Blackouts | Start inclusive/end exclusive; missing, malformed or inverted intervals fail init when enabled | Example fixture inputs/journal and rejection rows |
| Logs/report reconciliation | No duplicate completed positions; gross plus signed history costs equals net; R denominator documented | CSV analyzer JSON, MT5 report and deals |
| Realistic research baseline | Fixed predefined inputs, actual costs, suitable ticks, later untouched out-of-sample | Saved `.set`, data and reports with complete run manifest |

A journal replay exercise must preserve the same tester time progression and history, rather than start an independent test with an old run ID. Save the original files before experimenting with corrupted/missing state. An independent test needs a fresh run ID.
