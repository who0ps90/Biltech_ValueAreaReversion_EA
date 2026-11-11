# Reproducible research protocol

This project implements an operational interpretation of value-area reversion. It does not reproduce a third-party indicator. Its purpose is to measure expectancy after costs. No profitable result is supplied or implied.

## Freeze the experiment before viewing its result

Record the broker/server, symbol including suffix, account currency, deposit, leverage, MT5 build, source revision/hash, exported `.set`, test interval, modeling mode, execution delay, commissions, swap, data provenance and timezone rules. Use a unique `InpRunId` for each independent run. Preserve the Tester report, journal and all EA CSVs together. Reuse a run ID only for deliberate continuation of the same interrupted run, with its journal files retained.

Choose a historical development interval and a later, untouched out-of-sample interval in advance. Do not tune the example presets to an attractive equity curve. Test M15 and M30 as separate experiments. Treat 70% and 50% value areas as separate predefined experiments, for example `gold_M15_VA70` and `gold_M15_VA50`. Report every planned result, including configurations that lose or cannot trade because data fails validation.

Use the broker's actual chart symbol for both signals and execution. A CFD is not interchangeable with its related futures contract. Different broker contracts, quote activity, trading hours, time mappings and costs may produce different results.

## Verify data and clock mapping first

1. Obtain the broker's historical UTC offset convention, including the transition rule and dates. Do not infer history from the terminal's present offset. Configure the explicit fixed, EU or US rule that actually matches the tested history; split a test if the broker changed its convention. The supplied clock supports 2007–2099, and does not model exceptional legal changes outside the selected rules.
2. Check logged broker, UTC and New York times around the March and November US transitions, and the March/October EU transitions when relevant. Ambiguous repeated broker timestamps must not silently acquire an offset. Check New York 18:00 profile boundaries and local entry/forced-exit times on both sides of transitions.
3. Inspect M1 coverage for several ordinary sessions, a holiday, a shortened day and a weekend. The conservative baseline requires the greater of 1,000 completed M1 bars and 90% of elapsed UTC session minutes, no interior gap above 90 minutes and no leading/trailing gap above 180 minutes. A scheduled closure can still fail these checks: it is skipped, not repaired or substituted with an older valid session. Changing coverage thresholds is a documented experimental change, never proof that missing bars are harmless.
4. Prefer **Every tick based on real ticks** for baseline tests with suitable broker history. Read the Tester journal and report for missing data and modeled portions. Intrabar stop/target ordering and executable spreads need tick data; bar-only modes cannot validate those details. MT5 documents historical Bid/Ask spread handling and tick generation in its [testing reference](https://www.mql5.com/en/docs/runtime/testing).

## Visual audit before a long baseline

Run a short interval with visualization enabled. Record screenshots and CSV row identifiers for at least three long and three short setups when available, and rejected cases as well. If a side produces no examples, extend the audit interval without changing rules and report that limitation.

For each audited trade, independently inspect the prior completed session's M1 bars and profile, frozen VAL/VAH/POC, breakout bar zero, a later weakening candle, reclaim bar number, body engulfing, selected volume source, excursion extreme and ATR available at reclaim close. Check the order occurs only on the first tick of the next signal candle, with the executable Bid/Ask, normalized protective prices and downward-rounded size. Compare actual deal timestamps/prices, commissions, swap, exit reason, initial risk and R with the Tester deal history.

Check the same interval with visualization disabled using the identical inputs and data. The profile and signal algorithms are shared. Compare the CSV event sequence and trades; investigate any discrepancy before proceeding. Chart objects are presentation only.

## Baseline and robustness

Run one symbol per test, optimization disabled. Keep the risk and strategy baseline unchanged. Configure a broker-specific maximum spread in **points**, not price units or ticks. Set an account-currency round-trip commission estimate per lot and per-side slippage allowance in ticks from evidence. These inputs change the EA's filter and sizing; they do not charge simulated deals. Configure actual Tester commission/swap/execution settings separately and inspect resulting history so the estimate is not mistaken for paid costs.

The initial New York calendar day is locked unless an explicit initial-day equity is supplied. Start sufficiently early for M1 history and the previous completed profile; allow a complete day for normal daily equity initialization. New days use equity at the first observed tick, because midnight may have no tradable tick. Force-exit requests remain due across a closure until a tradable tick permits completion.

After a baseline, predefined sensitivity runs can raise costs/delay and change the requested signal timeframe/value area. Do not silently mix them into one reported baseline. Evaluate the reserved out-of-sample period once the experiment is fixed. This tester-only release requires a separately reviewed demo-enabled execution build before any demo forward test. Do not attach it to a live account; it intentionally refuses non-tester initialization.

## Required results

Export the MT5 **Backtest** report and retain its equity curve. MT5's report provides trade count, net profit, profit factor, expected payoff, drawdown and consecutive-loss measures; see the [official report guide](https://www.metatrader5.com/en/terminal/help/algotrading/testing_report). Report the actual account-currency costs alongside those results. Maximum equity drawdown must come from the tick-by-tick Tester equity path, not from closed-trade CSV balances.

Use `Tests/analyze_logs.py` on the completed-trade CSV to obtain overall, long/short and New York exit-month trade counts, net P/L, profit factor, expected payoff, win rate, mean winning/losing R and maximum consecutive closed losses. The script is a post-processing convenience, not an independent backtester. It does not infer unrealized drawdown or recreate market execution. Reconcile its totals with MT5; investigate rather than discard unexplained differences.

Include sample size, test dates, data deficiencies, all skipped-session counts, and every known unperformed validation. Do not claim positive expectancy without an actual reproducible cost-inclusive backtest, or generalization across brokers or markets. A finite backtest does not establish future performance.

