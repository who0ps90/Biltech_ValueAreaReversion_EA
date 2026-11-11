"""Synthetic post-processor checks; these do not execute any MQL source."""
import unittest
from pathlib import Path
from unittest.mock import patch

from analyze_logs import load_trades, report


class AnalyzeLogsTests(unittest.TestCase):
    def test_stats_costs_months_directions_and_loss_streak(self):
        content = "position_id,direction,exit_utc,exit_ny,net_pl,initial_risk,commission,swap,fees,holding_seconds\n"
        content += "1,BUY,2024.02.01 00:00:00,2024.01.31 19:00:00,20,10,-1,0,0,60\n"
        content += "2,SELL,2024.02.01 15:00:00,2024.02.01 10:00:00,-10,10,-1,0,0,120\n"
        content += "3,SHORT,2024.02.01 16:00:00,2024.02.01 11:00:00,-5,10,-1,0,0,180\n"
        content += "4,LONG,2024.02.01 17:00:00,2024.02.01 12:00:00,0,10,-1,0,0,240\n"
        with patch.object(Path, "read_bytes", return_value=content.encode("utf-16")):
            result = report(load_trades(Path("synthetic_trades.csv")))
        overall = result["overall"]
        self.assertEqual(overall["trades"], 4)
        self.assertEqual(overall["net_pl"], 5)
        self.assertAlmostEqual(overall["profit_factor"], 20 / 15)
        self.assertEqual(overall["expected_payoff"], 1.25)
        self.assertEqual(overall["win_rate_pct"], 25)
        self.assertEqual(overall["mean_winner_r"], 2)
        self.assertEqual(overall["mean_loser_r"], -.75)
        self.assertEqual(overall["maximum_consecutive_closed_losses"], 2)
        self.assertEqual(overall["commission"], -4)
        self.assertEqual(result["month"]["2024-01"]["trades"], 1)
        self.assertEqual(result["direction"]["SHORT"]["net_pl"], -15)

    def test_duplicate_position_rejected(self):
        content = "position_id,direction,exit_utc,exit_ny,net_pl\n1,LONG,2024.01.01 12:00:00,2024.01.01 07:00:00,5\n"
        content += "1,LONG,2024.01.01 12:00:00,2024.01.01 07:00:00,5\n"
        with patch.object(Path, "read_bytes", return_value=content.encode("utf-8")):
            with self.assertRaisesRegex(ValueError, "duplicate completed"):
                load_trades(Path("synthetic_trades.csv"))

    def test_no_loss_profit_factor_is_null(self):
        result = report([dict(direction="LONG", exit_utc="2024.01.01 12:00:00",
                              exit_ny="2024.01.01 07:00:00", month="2024-01",
                              net_pl=5, realized_r=None)])
        self.assertIsNone(result["overall"]["profit_factor"])

    def test_combined_deals_excluded_from_completed_summary(self):
        content = "event,position_id,direction,exit_utc,exit_ny,net_pl\n"
        content += "DEAL,1,LONG,2024.01.01 12:00:00,2024.01.01 07:00:00,5\n"
        content += "CLOSED,1,LONG,2024.01.01 12:00:00,2024.01.01 07:00:00,5\n"
        with patch.object(Path, "read_bytes", return_value=content.encode("utf-8")):
            trades = load_trades(Path("synthetic_trades.csv"))
        self.assertEqual(len(trades), 1)
        self.assertEqual(trades[0]["net_pl"], 5)

    def test_mixed_ownership_rejected(self):
        content = "event,position_id,direction,exit_utc,exit_ny,net_pl,annotation\n"
        content += "CLOSED,1,LONG,2024.01.01 12:00:00,2024.01.01 07:00:00,5,OWNERSHIP_CONFLICT\n"
        with patch.object(Path, "read_bytes", return_value=content.encode("utf-8")):
            with self.assertRaisesRegex(ValueError, "mixed ownership"):
                load_trades(Path("synthetic_trades.csv"))


if __name__ == "__main__":
    unittest.main()
