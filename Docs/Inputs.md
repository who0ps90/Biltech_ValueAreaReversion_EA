# Input reference

Defaults describe the delivered baseline, not validated parameters. All time-of-day integers are minutes after midnight: `hour * 60 + minute`. Clock and spread defaults are intentionally incomplete so initialization requires broker research. The `.set` presets store enum values as integers.

## Identity and historical clock

| Input | Default | Meaning |
|---|---|---|
| `InpRunId` | `research_001` | Local state/log identity, at most 50 characters. Use a fresh ID for every independent test. The same ID restores its journal; rewound time, changed material inputs/account/currency/margin mode or missing recorded entry deals are rejected. Use simple letters, digits, `_` and `-` to avoid sanitized filename collisions. |
| `InpConfigLabel` | `UNVALIDATED_baseline` | Human-readable label; logs append a hash of the material configuration and blackout content. Label is descriptive, not proof of validation. |
| `InpMagic` | `26002501` | Nonzero EA ownership identifier. Keep isolated from other strategies. One symbol/instance per test is supported. |
| `InpSessionMode` | `BV_NEW_YORK_SESSION` (`0`) | `0`: New York 18:00 to next 18:00. `BV_BROKER_CUSTOM_SESSION` (`1`): configured daily broker boundary. Entry/risk/exit times remain New York based in both modes. |
| `InpBrokerOffsetRule` | `BV_OFFSET_UNCONFIGURED` (`0`) | **Must configure.** `BV_OFFSET_FIXED=1`, `BV_OFFSET_EU=2`, `BV_OFFSET_US=3`. No current terminal offset inference. |
| `InpBrokerWinterUTCMinutes` | `120` | Broker minus UTC in minutes; fixed offset for all dates in FIXED mode, winter offset otherwise. Range −840 to +840. Default is illustrative until verified. |
| `InpBrokerSummerUTCMinutes` | `180` | Summer broker-minus-UTC offset in seasonal modes; must equal winter +60 minutes and remain within ±840. Ignored for FIXED. |
| `InpCustomBoundaryMinutes` | `1080` (18:00) | Broker-local profile boundary when custom mode is selected. Range 0–1439. New York mode always uses 18:00 NY. |

Supported calendar labels and conversions are 2007–2099 inclusive. EU transitions occur at 01:00 UTC on the last Sundays of March and October. US broker mode follows the **New York transition instants**: second Sunday in March at 07:00 UTC and first Sunday in November at 06:00 UTC. It does not mean 02:00 on any arbitrary broker clock. New York follows these post-2007 US rules with UTC−5/UTC−4. Repeated autumn broker hours have two UTC candidates and are rejected; nonexistent spring timestamps have none. Missing/ambiguous mapping fails initialization when detected there and creates a persistent operational lock when detected at runtime, requiring corrected configuration/data and restart. Custom boundaries that fall in a gap/fold also fail. Exceptional historical rule changes need a separate verified implementation or split tests.

## Profile and signal

| Input | Default | Meaning |
|---|---|---|
| `InpVolumeMode` | `BV_AUTO` (`2`) | `BV_TICK_VOLUME=0`, `BV_REAL_VOLUME=1`, `BV_AUTO=2`. AUTO pins one source selected from all prior profile bars. |
| `InpProfileRows` | `100` | Requested maximum histogram rows, 1–10,000 at initialization. Tick alignment may yield fewer rows. |
| `InpValueAreaPercent` | `70.0` | Contiguous included-volume target, greater than 0 and at most 100. A 50% experiment must be recorded separately. |
| `InpMinProfileM1Bars` | `1000` | Minimum available completed M1 observations; at least 1. |
| `InpMinProfileCoveragePercent` | `90.0` | Required share of session UTC minutes represented by completed M1 bars, greater than 0 and at most 100. Effective minimum is the greater of the absolute minimum and the rounded-up coverage requirement. A normal 24-hour session requires 1,296 bars at 90%; 23/25-hour sessions use their actual elapsed minutes. |
| `InpMaxProfileGapMinutes` | `90` | Maximum absent interior M1 minutes between successive available bars. A 91-minute timestamp difference represents 90 absent minutes. Nonnegative. |
| `InpMaxProfileEdgeGapMinutes` | `180` | Maximum time without bars at either session edge, using the first M1 open and last M1 close. Nonnegative. |
| `InpSignalTimeframe` | `PERIOD_M15` (`15`) | Explicit standard timeframe from M1 through D1. `PERIOD_CURRENT` is rejected. M30 is `30`; large bars that straddle a profile/offset boundary are skipped. |
| `InpMaxReclaimBars` | `5` | Positive number of candles after breakout bar zero in which reclaim may confirm; maximum included. |
| `InpRequireEngulfing` | `true` | Require reclaim body to cover immediately previous body. Disabling does not remove directional/previous-opposite requirements. |
| `InpEntryStartNYMinutes` | `585` (09:45) | Inclusive entry-window start, NY local. Gold preset uses 525 (08:45). |
| `InpEntryEndNYMinutes` | `690` (11:30) | Exclusive NY end. Gold preset uses 660 (11:00). Start greater than end means overnight; equal endpoints mean all day. |
| `InpMaxEntryDelaySeconds` | `60` | Maximum observed tick delay from next signal-bar start; nonnegative and shorter than signal timeframe. The first opportunity is consumed even when rejected; no later retry. |

Missing/nonconsecutive previous signal candles reset both excursion states. A contiguous previous candle from the prior session may provide the close reference for a fresh breakout in the new session; pending setups still reset. A signal candle spanning a profile-session boundary or an offset transition is skipped, because its OHLC cannot be split without introducing a different signal definition. A flat profile is represented by one tick-wide bin; ordinary tick-aligned closes have no strictly interior tick price, so its reclaims cannot qualify. Zero-range individual M1 bars still conserve volume.

## Protection, costs and daily risk

| Input | Default | Meaning |
|---|---|---|
| `InpATRPeriod` | `14` | Positive ATR lookback on signal timeframe. `iATR` value is read for the closed reclaim candle. |
| `InpBufferTicks` | `2.0` | Nonnegative minimum protective buffer in actual symbol ticks. At least one buffer component must be positive. |
| `InpATRBufferFraction` | `0.10` | Nonnegative multiplier of reclaim-close ATR. Stop buffer is maximum of this component and tick component. Both components zero is rejected. |
| `InpMinRewardRisk` | `1.5` | Positive minimum estimated net target reward divided by estimated SL risk, after configured allowance. |
| `InpRiskPercent` | `0.25` | Positive percentage of current equity budgeted per trade, including cost allowance. `0.25` means 0.25%, not 25%. |
| `InpDailyLossPercent` | `0.75` | Positive loss percentage of recorded New York day-start equity; tracks this EA's attributable net plus floating P/L. |
| `InpInitialDayEquity` | `0.0` | Optional explicit baseline for the initial partial NY day. Zero leaves a cold start more than the entry-delay tolerance past midnight locked until the next NY day. A missing initial day snapshot with existing EA activity locks even when a baseline is supplied. Use only a researched true baseline. |
| `InpCommissionRoundTurnPerLot` | `0.0` | Nonnegative estimated **round-trip account-currency cost per 1.0 lot**, used in sizing/RR only. Configure actual Tester commissions separately. Zero does not assert that your broker is commission-free. |
| `InpSlippageTicksPerSide` | `0.0` | Nonnegative estimated adverse slippage per side in actual ticks; two sides are included in allowance. Does not inject realized Tester slippage. |
| `InpMaxSpreadPoints` | `0.0` | **Required positive broker-specific maximum** `(Ask−Bid)/SYMBOL_POINT`. Units are points, not ticks/pips or price units. Gold/index names do not establish a universal threshold. |
| `InpOrderDeviationPoints` | `20` | Unsigned request price-deviation tolerance in broker points. Execution mode determines its effect; it is not a guaranteed fill/slippage cap. |
| `InpForceExit` | `true` | Request closure of owned exposure at cutoff; continued retries at available ticks if still open. |
| `InpForceExitNYMinutes` | `955` (15:55) | NY local cutoff, 0–1439. New entries after cutoff are rejected when forced exit enabled. Exposure surviving into a later NY day remains due for closure. |

The initial R denominator is actual-fill-to-original-SL account-currency loss plus the configured round-trip allowance, recorded contemporaneously and accumulated over actual entry fills. Realized R is actual net history P/L divided by that original monetary risk. If the original SL or contemporaneous monetary-risk record is unavailable, R is unavailable rather than reconstructed using later currency-conversion rates. Estimates already included in risk are not deducted again from realized history net P/L.

## Blackouts and visuals

| Input | Default | Meaning |
|---|---|---|
| `InpUseBlackouts` | `false` | Enable manual UTC intervals. Missing/invalid requested file fails initialization. Does not fetch any external calendar. |
| `InpBlackoutFile` | `Biltech_blackouts.csv` | Relative file in local tester agent `MQL5\Files`; UTF-8 **without BOM**, exact three-column header. No automatic tester transfer is declared for this dynamic filename; copy manually before the test. Its content contributes to configuration identity. |
| `InpShowVisuals` | `true` | Show frozen lines, setup/window/day-risk status and entry/SL/TP markers when Tester visualization is enabled. Algorithms/logging are shared with nonvisual tests. |

Logs are `Biltech_<RunId>_<Symbol>_<Magic>_signals.csv`, `_trades.csv`, and `_journal.csv` in the local tester file sandbox. Run and symbol filenames are sanitized. Reusing sanitized names for different input strings risks a deliberate collision check; avoid punctuation-only name differences.
