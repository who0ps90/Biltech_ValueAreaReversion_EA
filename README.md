# Biltech_ValueAreaReversion_EA

A focused MT5 Expert Advisor for historical research of previous-session value-area reversion on the current chart symbol. It uses a frozen M1 OHLCV profile, completed-candle long/short state machines, executable-price risk checks and local audit logs. It intentionally initializes **only in the Strategy Tester**. No live or demo-account trading is enabled.

**Status:** EA and native test suite (171 assertions) compiled with **0 errors and 0 warnings** in MetaEditor 5.0.0.6281. Native test execution, broker execution validation and historical backtests remain unperformed. A strategy run additionally requires a verified broker timezone mapping, spread threshold and chosen date/data experiment. See [validation evidence](Docs/Validation.md) for exact scope. The three market presets are **UNVALIDATED**, require broker configuration and are not optimized recommendations.

## Files and installation

1. In MT5 choose **File → Open Data Folder**. Under `MQL5\Experts`, create `Biltech_ValueAreaReversion_EA` and copy the main `.mq5`, `Include`, `Tests`, `Presets`, `Examples` and documentation into it, preserving folders.
2. Press **F4** for MetaEditor. Open `Experts\Biltech_ValueAreaReversion_EA\Biltech_ValueAreaReversion_EA.mq5`, press **F7**, and inspect every error and warning. A successful build should produce its `.ex5` beside the source. The files use relative quoted includes; keep `Include` beside the main source.
3. Open `Tests\BVSelfTest.mq5` in MetaEditor and compile it separately. Run this test EA in the Strategy Tester and retain its journal. It never submits trading requests. A host Python pass does not replace this native test.
4. Refresh the MT5 Navigator if necessary. Open **View → Strategy Tester** (**Ctrl+R**) and select the compiled strategy EA. Do not attach it to a normal chart: non-tester initialization is deliberately rejected.

No external Python package, DLL, network service or economic-calendar API is required by the EA. Python 3 is optional for packaging checks and post-processing.

## Strategy rules

### Previous completed profile

The analytical session defaults to **18:00 New York local time to the next 18:00**. The immediately preceding completed session supplies VAL, VAH and POC, frozen throughout the next session. A custom daily boundary in broker local time is available. Empty/invalid prior sessions do not trigger a search for an older profile. The same builder runs in visual and nonvisual tests.

The baseline uses up to 100 rows and 70% volume. Bin edges align to the actual symbol tick size: origin rounds the session low down to a tick; width is a whole number of ticks, rounded up to cover the range within the requested row count. Consequently actual rows can be fewer than requested. Nonzero-range M1 bars distribute volume in proportion to overlap with each bin; zero-range bars assign all volume to their containing bin. Bins are half-open except for the final upper edge; an observation exactly on an interior edge belongs to the higher bin. Floating-point residuals go to the final overlapping bin and total volume is checked for conservation.

POC is the midpoint of the highest-volume bin. Exact ties select the lowest-price bin. Value area starts there and expands contiguously toward the larger adjacent volume; ties expand toward lower prices first. VAL/VAH are the outer edges of included bins. Bin **edges** align to ticks; a midpoint POC can lie at half a tick. This is an OHLCV approximation, not exchange tick-by-tick volume at price.

TICK_VOLUME uses broker quote activity. REAL_VOLUME requires positive real volume throughout the needed data. AUTO selects real volume only when every profile M1 bar has positive real volume, otherwise uses tick volume consistently with a visible warning if all tick volumes are usable. The chosen source is pinned for the next trading session's candles. Required real volume missing later invalidates that profile for the rest of the session; no mid-session fallback occurs.

Conservative default coverage requires at least the greater of **1,000 completed M1 bars** and **90% of the session's UTC minutes**, no interior missing interval longer than 90 minutes, and leading/trailing gaps no longer than 180 minutes. These checks deliberately skip many shortened/holiday sessions and cannot certify complete tick history. Inspect skip reasons before changing thresholds.

### Closed-candle setup

Signal timeframe defaults to M15. Each closed candle is processed once, in chronological order. Long and short states are separate; each new profile session resets both. A setup cannot cross the session boundary. A contiguous candle immediately before the new session may supply only the prior close for a new boundary crossing; breakout bar zero itself belongs to the new session.

| Stage | Long | Short |
|---|---|---|
| Breakout, bar 0 | Prior close ≥ VAL; new close < VAL | Prior close ≤ VAH; new close > VAH |
| Later weakening | A bearish candle closes below VAL with volume strictly below breakout volume | A bullish candle closes above VAH with volume strictly below breakout volume |
| Reclaim, bars 1–5 | Bullish, close strictly inside value; immediately previous candle bearish; body engulfs it; volume strictly above breakout volume | Bearish, close strictly inside value; immediately previous candle bullish; body engulfs it; volume strictly above breakout volume |
| Extreme | Lowest low from breakout through reclaim | Highest high from breakout through reclaim |

Weakening must occur **after** the breakout and **before** reclaim. Continuing outside value does not reset bar zero. With engulfing enabled, long body conditions are `open <= previous close` and `close >= previous open`; short mirrors them. Disabling engulfing removes only the body-coverage test: candle directions and immediate preceding opposite candle still apply.

A setup expires after its configured maximum reclaim bar (default five). An unconfirmed return to value, a close at the reclaim boundary, a close reaching/beyond the opposite boundary, or a session change invalidates it. Boundary equality cannot confirm, because reclaim must be strictly inside value. A fresh qualifying crossing is required after invalidation. Doji candles qualify as neither bullish nor bearish.

### Entry, protection and risk

Confirmation creates one entry opportunity at the first observed tick of the **next signal candle**, within the configured maximum delay (default 60 seconds). A late historical/backlog signal or failed attempt is logged and not retried. The entry must still fall in the New York entry window; start is inclusive, end exclusive. A closed market does not guarantee a candle-open fill.

Buys use Ask, sells use Bid. Stops lie beyond the inclusive excursion extreme by `max(2 ticks, 0.10 × ATR(14))` at reclaim close. Long TP is frozen VAH; short TP is frozen VAL. Prices round to real tick increments, with stops outward and targets conservatively inward. Broker stop/freeze distances, valid quote, target side, spread, margin, supported order/protection/filling mode, ownership, daily limit and net reward/risk are rechecked. Targets never move to pass the filter.

Baseline minimum estimated reward/risk is 1.5. Monetary risk uses `OrderCalcProfit` and account equity; the baseline budget is 0.25% of current equity. Estimated round-trip commission per lot plus two adverse slippage sides are added to stop loss and deducted from target reward. Spread is already represented by executable entry and exit-side prices and is not separately added. Volume rounds **down** to symbol step and is capped by broker maximum/limit. If minimum volume would exceed budget, the trade is rejected. Margin is checked before submission. [MetaQuotes documents `OrderCalcProfit` in account currency.](https://www.mql5.com/en/docs/trading/ordercalcprofit)

Default restrictions are one EA position per symbol and one filled trade per direction per profile session. There is no averaging, grid, martingale, pyramiding, trailing, break-even or partial-exit strategy. Foreign hedging positions are left alone. A netting symbol with foreign ownership/exposure blocks entry; ownership ambiguity must fail safely rather than modify someone else's position.

Default forced exit is **15:55 New York**, retried at available ticks until closed. Existing positions remain managed outside entry windows. A due exit remains due across a market closure. New York midnight-to-midnight daily loss compares this EA's realized net plus floating P/L with 0.75% of recorded start-of-day equity; breach blocks entries for the rest of that day and requests closure. Gaps, slippage and unavailable markets can exceed the threshold.

The first partial New York day is locked unless its baseline equity is explicitly supplied. An initial missing day snapshot with existing EA activity stays locked even with an explicit baseline. Subsequent day baselines use the first observed tick. Journal plus deal history restore baselines, filled-direction limits, attempts and accounting after restart. Continuation checks require recorded entry deals to remain present and account/configuration identity to match. Preserve all files/history for continuation. A new independent test needs a new run ID so old state cannot silently contaminate it.

## Exact baseline test procedure

1. Select the broker's intended gold/Nasdaq-100/US30 **symbol including suffix**. The EA uses `_Symbol` for data and execution and never substitutes a futures feed. Record symbol specification, account currency, deposit, leverage and MT5 build.
2. In Tester settings select **Single test**, your historical date range and **Every tick based on real ticks** when suitable broker history exists. Turn optimization off. Set deposit/currency/leverage and actual commission/swap/execution assumptions. Avoid profit-in-pips mode, which omits relevant account-currency costs. The EA's cost estimates are filtering/sizing allowances, not a replacement for actual Tester charges. [Official Tester settings](https://www.metatrader5.com/en/terminal/help/algotrading/testing) describe modeling and account configuration.
3. In **Inputs → Load**, choose one `Presets\*_UNVALIDATED.set`. Set a unique run ID; configure the historical broker timezone rule and offsets, broker-specific maximum spread in points, and evidenced commission/slippage allowances. The supplied presets intentionally fail initialization until the clock and spread are configured. Save the resulting `.set` under a distinct experiment name.
4. Allow M1 warm-up and at least a full prior analytical session. Check the data and journal for gaps, source warnings and skipped profiles. Review broker/UTC/New York timestamp rows around DST changes. Use **M15** for the baseline input; the strategy input controls signals, so do not assume Tester display period overrides it.
5. Enable **Visualization** for a short audit interval. Verify examples of both sides and rejection cases using [the research protocol](Docs/ResearchProtocol.md). Compare an identical nonvisual run. Preserve evidence before running a longer baseline.
6. Start the fixed baseline. Export the Tester report and retain journal, signals, trades and state files. Give each independent run a new run ID. Test M30 separately; test 50% versus 70% value area as separate predefined experiments. Reserve a later untouched interval for out-of-sample evaluation. A demo forward test requires a separately reviewed demo-enabled version; this release remains tester-only.

## CSVs and manual blackouts

Public EA CSVs use UTF-8 with quoted fields and no multiline cells. The signals file records configuration, clocks, profile/session, setup candles and volumes, weakening/engulfing, excursion, ATR/buffer, planned/actual entry, protection, spread, estimated R/R, budget/volume and accepted/rejected reasons. The trades file contains actual deal rows and one `CLOSED` summary per completed position with history costs, net P/L, initial monetary risk, realized R and holding time. The private state journal is tab-delimited despite its `.csv` extension; preserve it unchanged for continuation and duplicate suppression. Journaled audit rows can repair interrupted writes on restart; malformed/partial public CSVs fail clearly instead of being silently appended to.

MT5 restricts files to its file sandbox. For local testing look under the local tester agent's `MQL5\Files` directory, not necessarily the terminal's ordinary `MQL5\Files`. Use the agent path identified by the Tester journal. Remote/cloud agents have separate sandboxes; use local agents for auditable file collection and manual blackout inputs. [Official `FileOpen` documentation](https://www.mql5.com/en/docs/files/fileopen) describes these paths.

Blackout filtering defaults off. Copy the example to the testing agent's file sandbox and set its relative filename. For a reproducible local test, place it under that agent's `MQL5\Files` before starting. CSV header is exactly `start_utc,end_utc,label`; timestamps are UTC `YYYY.MM.DD HH:MM:SS`, with no timezone suffix. Intervals use start-inclusive/end-exclusive semantics. Replace the illustrative dates and labels with researched event windows. Enabling the filter with a missing/malformed file must fail clearly. No live calendar request is made.

To summarize one run's completed trades with Python 3:

```powershell
python Tests/analyze_logs.py "C:\path\to\run_trades.csv" --output "C:\path\to\summary.json"
```

The report contains trade count, net profit, profit factor, expected payoff, win rate, mean winner/loser in R, maximum consecutive closed losses, long/short and New York exit-month results, history costs and mean holding time. It counts only `CLOSED` rows; mixed-ownership positions and duplicate completed IDs cause a clear error. Zero-net trades count toward the win-rate denominator and break loss streaks. A valid file with no completed positions reports zero trades; unavailable ratios and a profit factor without net losing trades are `null`. Use the **MT5 Tester report** for maximum **equity** drawdown; trade CSVs cannot reconstruct it. Reconcile CSV totals against the Tester history/report.

## Further reading

- [Input reference](Docs/Inputs.md)
- [Validation checklist and recorded evidence](Docs/Validation.md)
- [Assumptions and unresolved limitations](Docs/AssumptionsAndLimitations.md)
- [Research and reporting protocol](Docs/ResearchProtocol.md)

No historical backtest was run in this environment. Profitability and generalization across brokers/markets remain unmeasured.
