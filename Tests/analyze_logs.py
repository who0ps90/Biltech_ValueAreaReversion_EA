#!/usr/bin/env python3
"""Summarize completed-trade CSVs. Does not run or validate the MQL5 strategy."""
from __future__ import annotations

import argparse
import csv
import io
import json
import math
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from statistics import mean


ALIASES = {
    "position_id": ("position_id", "position_identifier", "position"),
    "direction": ("direction", "side"),
    "exit_ny": ("exit_ny", "exit_ny_time", "close_ny", "ny_exit"),
    "exit_utc": ("exit_utc", "close_utc", "exit_time_utc"),
    "net_pl": ("net_pl", "net_pnl", "net_profit", "net"),
    "gross_pl": ("gross_pl", "gross_pnl", "gross_profit", "gross"),
    "commission": ("commission", "commissions"),
    "swap": ("swap",),
    "fees": ("fees", "fee"),
    "initial_risk": ("initial_risk", "initial_monetary_risk"),
    "realized_r": ("realized_r", "r_multiple", "realized_r_multiple", "r"),
    "holding_seconds": ("holding_seconds", "hold_seconds", "duration_seconds"),
}


def decode_csv(path: Path) -> str:
    raw = path.read_bytes()
    if raw.startswith((b"\xff\xfe", b"\xfe\xff")):
        return raw.decode("utf-16")
    try:
        return raw.decode("utf-8-sig")
    except UnicodeDecodeError:
        return raw.decode("cp1252")


def number(value: str | None, *, optional: bool = False) -> float | None:
    if value is None or not value.strip():
        if optional:
            return None
        raise ValueError("missing numeric value")
    parsed = float(value)
    if not math.isfinite(parsed):
        raise ValueError(f"non-finite value: {value!r}")
    return parsed


def load_trades(path: Path, filters: list[str] | None = None) -> list[dict]:
    text = decode_csv(path)
    try:
        dialect = csv.Sniffer().sniff(text[:8192], delimiters=",;\t")
    except csv.Error:
        dialect = csv.excel
    reader = csv.DictReader(io.StringIO(text), dialect=dialect)
    if not reader.fieldnames:
        raise ValueError("empty CSV or missing header")
    fields = {field.strip().lower(): field for field in reader.fieldnames}
    resolved = {
        key: next((fields[alias] for alias in aliases if alias in fields), None)
        for key, aliases in ALIASES.items()
    }
    for required in ("net_pl", "direction", "exit_utc", "exit_ny"):
        if not resolved[required]:
            raise ValueError(f"missing required column {required!r}; available: {', '.join(fields)}")
    predicates = []
    for expression in filters or []:
        key, separator, value = expression.partition("=")
        if not separator or key.lower() not in fields:
            raise ValueError(f"filter must be an existing column=value: {expression!r}")
        predicates.append((fields[key.lower()], value))
    trades, seen = [], set()
    for line, row in enumerate(reader, start=2):
        if not any((value or "").strip() for value in row.values()):
            continue
        if any((row.get(key) or "").strip() != value for key, value in predicates):
            continue
        if "event" in fields and (row.get(fields["event"]) or "").strip().upper() != "CLOSED":
            continue
        if "annotation" in fields and "OWNERSHIP_CONFLICT" in (row.get(fields["annotation"]) or ""):
            raise ValueError(f"{path.name}:{line}: completed position has mixed ownership; reconcile manually")
        def cell(key):
            return (row.get(resolved[key], "") or "").strip() if resolved[key] else ""
        # A combined events file may contain entry/deal rows. Only finalized rows
        # carrying both exit clocks are eligible for this trade summary.
        if not cell("exit_utc") or not cell("exit_ny"):
            continue
        try:
            trade = {key: number(cell(key), optional=True) for key in (
                "gross_pl", "commission", "swap", "fees", "initial_risk",
                "realized_r", "holding_seconds")}
            trade["net_pl"] = number(cell("net_pl"))
            direction = cell("direction").upper()
            if direction in ("1", "BUY", "LONG"):
                direction = "LONG"
            elif direction in ("-1", "SELL", "SHORT"):
                direction = "SHORT"
            else:
                raise ValueError(f"unrecognized direction: {direction!r}")
            trade.update(direction=direction, exit_utc=cell("exit_utc"),
                         exit_ny=cell("exit_ny"), position_id=cell("position_id"))
            stamp = datetime.strptime(trade["exit_ny"].replace(".", "-"), "%Y-%m-%d %H:%M:%S")
            datetime.strptime(trade["exit_utc"].replace(".", "-"), "%Y-%m-%d %H:%M:%S")
            trade["month"] = stamp.strftime("%Y-%m")
            if trade["realized_r"] is None and (trade["initial_risk"] or 0) > 0:
                trade["realized_r"] = trade["net_pl"] / trade["initial_risk"]
            # Duplicate completed positions would inflate research statistics.
            identity = trade["position_id"]
            if identity:
                if identity in seen:
                    raise ValueError(f"duplicate completed position_id {identity!r}; use one run/file")
                seen.add(identity)
            trades.append(trade)
        except (TypeError, ValueError) as exc:
            raise ValueError(f"{path.name}:{line}: {exc}") from exc
    # Timestamp strings use fixed-width ISO/MQL fields and sort chronologically.
    return sorted(trades, key=lambda trade: (trade["exit_utc"].replace(".", "-"), trade["position_id"]))


def summarize(trades: list[dict]) -> dict:
    winners = [trade for trade in trades if trade["net_pl"] > 0]
    losers = [trade for trade in trades if trade["net_pl"] < 0]
    profit = sum(trade["net_pl"] for trade in winners)
    loss = -sum(trade["net_pl"] for trade in losers)
    longest = streak = 0
    for trade in trades:
        streak = streak + 1 if trade["net_pl"] < 0 else 0
        longest = max(longest, streak)
    def average(items, field):
        values = [item[field] for item in items if item.get(field) is not None]
        return mean(values) if values else None
    def total(field):
        values = [trade[field] for trade in trades if trade.get(field) is not None]
        return sum(values) if values else None
    return {
        "trades": len(trades), "net_pl": sum(trade["net_pl"] for trade in trades),
        "profit_factor": profit / loss if loss else None,
        "profit_factor_note": "undefined: no net losing trades" if not loss else "",
        "expected_payoff": mean(trade["net_pl"] for trade in trades) if trades else None,
        "win_rate_pct": 100 * len(winners) / len(trades) if trades else None,
        "mean_winner_r": average(winners, "realized_r"),
        "mean_loser_r": average(losers, "realized_r"),
        "r_available_trades": sum(trade["realized_r"] is not None for trade in trades),
        "maximum_consecutive_closed_losses": longest,
        "mean_holding_seconds": average(trades, "holding_seconds"),
        "gross_pl": total("gross_pl"), "commission": total("commission"),
        "swap": total("swap"), "fees": total("fees"),
    }


def report(trades: list[dict]) -> dict:
    months = defaultdict(list)
    for trade in trades:
        months[trade["month"]].append(trade)
    return {
        "scope": "Completed positions only. Month is New York exit month. Costs retain history sign.",
        "limitations": "No equity drawdown: obtain it from the MT5 Tester equity path. No backtest is run.",
        "overall": summarize(trades),
        "direction": {side: summarize([trade for trade in trades if trade["direction"] == side])
                      for side in ("LONG", "SHORT")},
        "month": {month: summarize(group) for month, group in sorted(months.items())},
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv", type=Path, help="one EA completed-trade CSV for one run")
    parser.add_argument("--filter", action="append", default=[], metavar="COLUMN=VALUE",
                        help="optional exact row filter, repeat as needed")
    parser.add_argument("--output", type=Path, help="optional UTF-8 JSON report path")
    args = parser.parse_args()
    try:
        trades = load_trades(args.csv, args.filter)
        result = report(trades)
    except (OSError, ValueError) as exc:
        parser.error(str(exc))
    output = json.dumps(result, indent=2, allow_nan=False)
    if args.output:
        args.output.write_text(output + "\n", encoding="utf-8")
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
