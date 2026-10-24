from pathlib import Path
import csv
from decimal import Decimal
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest


@unittest.skipUnless(shutil.which("ledger"), "ledger required")
class FinanceDashboardTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.vault = self.root / "vault"
        self.vault.mkdir()
        self.journal = self.root / "main.ledger"
        self.journal.write_text("include entries.ledger\n")
        self.entries = self.root / "entries.ledger"
        self.entries.write_text("""P 2025-01-01 STOCK 10 SEK
P 2025-02-28 STOCK 20 SEK
P 2025-03-01 STOCK 999 SEK
P 2025-03-16 STOCK 5000 SEK
P 2025-01-01 EUR 10 SEK
P 2025-02-01 EUR 20 SEK

2024-12-01 Opening
    assets:cash  1000 SEK
    equity:opening

2025-01-02 Salary
    assets:cash  1000 SEK
    revenue:salary

2025-01-03 Groceries
    expenses:Food:Groceries  100 SEK
    assets:cash

2025-01-04 Transfer
    assets:savings  200 SEK
    assets:cash

2025-01-05 Investment
    assets:stocks  2 STOCK @ 10 SEK
    assets:cash  -20 SEK

2025-01-06 Credit card
    expenses:Travel  50 SEK
    liabilities:card  -50 SEK

2025-01-07 Foreign purchase
    expenses:Travel  2 EUR
    assets:cash  -2 EUR

2025-01-08 Company income
    assets:aktiebolag:cash  5000 SEK
    revenue:aktiebolag:sales  -5000 SEK

2025-01-09 Company expense
    expenses:aktiebolag:Services  1000 SEK
    assets:aktiebolag:cash  -1000 SEK

2025-02-03 Refund
    assets:cash  10 SEK
    expenses:Food:Groceries

2025-03-01 Salary
    assets:cash  9999 SEK
    revenue:salary
""")

    def run_sync(self, *arguments):
        return subprocess.run(
            [
                sys.executable,
                str(Path(__file__).with_name("finance.py")),
                "--ledger-file",
                str(self.journal),
                "--vault",
                str(self.vault),
                "--as-of",
                "2025-03-15",
                "--months",
                "2",
                *arguments,
            ],
            capture_output=True,
            text=True,
            env={**os.environ, "LEDGER_FILE": "/nonexistent"},
        )

    def note(self):
        return (self.vault / "Finance dashboard.md").read_text()

    def charts(self):
        return re.findall(r"```mermaid\n(.*?)```", self.note(), re.DOTALL)

    def test_net_worth_includes_liabilities_without_double_counting(self):
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        note = self.note()
        self.assertIn("Net worth · 13 797.00 SEK", note)
        self.assertIn("line [1830.00, 1840.00, 13797.00]", note)
        self.assertIn('"stocks · 1 998.00": 1998.00', note)
        self.assertIn("Assets · 2025-03-15", note)
        self.assertNotIn("<!-- finance:", note)
        self.assertNotIn(r"\u00b7", note)
        self.assertNotIn("aktiebolag", note)
        outside = re.sub(r"```mermaid\n.*?```", "", note, flags=re.DOTALL)
        self.assertEqual(
            re.sub(r"\A---\n.*?\n---\n", "", outside, count=1, flags=re.DOTALL).strip(),
            "",
        )
        self.assertTrue(note.startswith('---\ncategories:\n  - "[[System]]"\n---\n'))

    def test_expense_treemap_separates_debits_and_credits(self):
        with self.entries.open("a") as output:
            output.write(
                "\n2025-03-02 Food\n    expenses:Food:Groceries  100 SEK\n    assets:cash\n\n2025-03-03 Refund\n    assets:cash  25 SEK\n    expenses:Subscriptions\n"
            )
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        chart = next(c for c in self.charts() if "Expenses ·" in c)
        self.assertIn("treemap-beta", chart)
        self.assertIn("debits · 100.00", chart)
        self.assertIn("credits · -25.00", chart)
        self.assertIn('"Food · 100.00"', chart)
        self.assertIn('"Subscriptions · -25.00"', chart)
        self.assertIn('"Subscriptions · -25.00": 25.00', chart)
        self.assertIn("net 75.00", chart)
        self.assertIn("classDef", chart)
        self.assertIn("sankey-beta", self.note())

    def test_last_30_days_includes_today_and_excludes_day_31(self):
        with self.entries.open("a") as output:
            output.write(
                "\n2025-02-13 Outside\n    expenses:Outside  17 SEK\n    assets:cash\n\n2025-02-14 First day\n    expenses:First  19 SEK\n    assets:cash\n\n2025-03-15 Today\n    expenses:Today  23 SEK\n    assets:cash\n\n2025-03-16 Future\n    expenses:Future  29 SEK\n    assets:cash\n"
            )
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        chart = next(c for c in self.charts() if "Expenses ·" in c)
        self.assertIn("2025-02-14 – 2025-03-15", chart)
        self.assertIn('"First · 19.00"', chart)
        self.assertIn('"Today · 23.00"', chart)
        self.assertNotIn("Outside", chart)
        self.assertNotIn("Future", chart)

    def test_sankey_nets_expenses_before_routing_funds(self):
        with self.entries.open("a") as output:
            output.write(
                "\n2025-03-02 Food\n    expenses:Food  100 SEK\n    assets:cash\n\n2025-03-03 Refund\n    assets:cash  25 SEK\n    expenses:Subscriptions\n\n2025-03-04 Borrow\n    assets:cash  50 SEK\n    liabilities:card\n"
            )
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        chart = next(c for c in self.charts() if "sankey-beta" in c)
        self.assertIn('"revenue (9 999.00)"', chart)
        self.assertIn("liabilities (50.00)", chart)
        self.assertIn("Funds (10 049.00)", chart)
        self.assertIn("expenses (75.00)", chart)
        self.assertIn("assets (9 974.00)", chart)
        self.assertNotIn("expenses:", chart)
        self.assertNotIn("revenue:", chart)
        self.assertNotIn("liabilities:", chart)
        self.assertNotIn("assets:", chart)
        self.assertIn('"nodeColors":', chart)
        edges = [
            (a, b, Decimal(value))
            for a, b, value in csv.reader(
                io.StringIO(chart.split("sankey-beta\n", 1)[1].strip())
            )
        ]
        sources = {a for a, _, _ in edges}
        targets = {b for _, b, _ in edges}
        for node in sources & targets:
            self.assertEqual(
                sum(v for _, b, v in edges if b == node),
                sum(v for a, _, v in edges if a == node),
            )

    def test_posting_date_exchange_rates(self):
        result = self.run_sync("--as-of", "2025-01-30")
        self.assertEqual(result.returncode, 0, result.stderr)
        chart = next(c for c in self.charts() if "Expenses ·" in c)
        self.assertIn('"Travel · 70.00"', chart)
        self.assertIn('"Food · 100.00": 100.00', chart)

    def test_asset_credits_are_not_positive_holdings(self):
        with self.entries.open("a") as output:
            output.write(
                "\n2025-03-03 Overdraft\n    assets:overdraft  -20 SEK\n    equity:opening\n"
            )
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("13 777.00 SEK", self.note())
        chart = next(c for c in self.charts() if "treemap-beta" in c)
        self.assertNotIn("overdraft", chart)
        self.assertIn("Assets (positive balances)", chart)

    def investment_fixture(self):
        self.entries.write_text("""P 2025-02-01 AAA 10 SEK
P 2025-02-20 AAA 12 SEK
P 2025-03-15 AAA 15 SEK
P 2025-02-01 BBB 20 SEK
P 2025-03-10 BBB 19 SEK
P 2025-03-15 BBB 18 SEK

2025-02-01 Opening
    assets:investments:funds:bank:AAA  10 AAA @ 10 SEK
    assets:investments:stocks:bank:BBB  5 BBB @ 20 SEK
    equity:opening  -200 SEK

2025-02-20 Buy
    assets:investments:funds:bank:AAA  2 AAA @ 12 SEK
    assets:cash  -24 SEK

2025-03-10 Sell
    assets:investments:stocks:bank:BBB  -2 BBB @ 19 SEK
    assets:cash  38 SEK
""")

    def test_investment_holdings_and_revaluation_exclude_purchases_and_sales(self):
        self.investment_fixture()
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        note = self.note()
        self.assertIn('"AAA · 180.00 · Δ +56.00": 180.00', note)
        self.assertIn('"BBB · 54.00 · Δ -8.00": 54.00', note)
        self.assertIn("Δ +56.00", note)
        self.assertIn("Δ -8.00", note)
        self.assertIn("Price + FX", note)
        self.assertLess(note.index("Assets ·"), note.index("Price + FX"))

    def test_investment_headers_sum_price_fx_changes(self):
        self.investment_fixture()
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        chart = next(c for c in self.charts() if 'title: "Investments' in c)
        self.assertIn("Investments · Δ +48.00 SEK", chart)
        self.assertIn('"investments · 234.00 · Δ +48.00"', chart)
        self.assertIn('"funds · 180.00 · Δ +56.00"', chart)
        self.assertIn('"stocks · 54.00 · Δ -8.00"', chart)

    def test_six_charts_follow_the_requested_order(self):
        self.investment_fixture()
        with self.entries.open("a") as output:
            output.write(
                "\n2025-03-05 Spend\n    expenses:Food  5 SEK\n    assets:cash\n\n2025-03-06 Borrow\n    assets:cash  50 SEK\n    liabilities:card\n"
            )
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        charts = self.charts()
        self.assertEqual(len(charts), 6)
        for chart, title in zip(
            charts,
            [
                "Last 30 days",
                "Expenses",
                "Net worth",
                "Assets",
                "Investments",
                "Liabilities",
            ],
        ):
            self.assertIn(title, chart)

    def test_internal_investment_transfers_are_not_revaluation(self):
        self.investment_fixture()
        with self.entries.open("a") as output:
            output.write(
                "\n2025-03-14 Transfer\n    assets:investments:funds:other-bank:AAA  1 AAA\n    assets:investments:funds:bank:AAA  -1 AAA\n"
            )
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Δ +56.00", self.note())
        self.assertEqual(self.note().count('"AAA · 180.00 · Δ +56.00": 180.00'), 1)

    def test_liability_treemap_preserves_signed_balances(self):
        with self.entries.open("a") as output:
            output.write(
                "\n2025-03-02 Receivable\n    liabilities:Work  80 SEK\n    assets:cash\n"
            )
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        chart = next(c for c in self.charts() if "Liabilities ·" in c)
        self.assertIn("treemap-beta", chart)
        self.assertIn("debits · 80.00", chart)
        self.assertIn("credits · -50.00", chart)
        self.assertIn('"card · -50.00": 50.00', chart)
        self.assertIn('"Work · 80.00": 80.00', chart)
        self.assertIn("net 30.00", chart)
        self.assertIn("classDef", chart)
        debit_class = re.search(r'"debits · 80.00":::(c\d+)', chart)[1]
        credit_class = re.search(r'"credits · -50.00":::(c\d+)', chart)[1]
        self.assertIn(f"classDef {debit_class} fill:#397b45", chart)
        self.assertIn(f"classDef {credit_class} fill:#b74045", chart)

    def test_space_grouping_two_decimals_and_quoted_accounts(self):
        with self.entries.open("a") as output:
            output.write(
                '\n2025-03-02 Expense\n    expenses:Things, "stuff"  12000.45 SEK\n    assets:cash\n'
            )
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Things, ″stuff″ · 12 000.45", self.note())
        self.assertIn('"showValues": false', self.note())

    def test_generated_comments_are_removed_from_legacy_notes(self):
        self.assertEqual(self.run_sync().returncode, 0)
        path = self.vault / "Finance dashboard.md"
        charts = (
            self.note()
            .replace("<!-- finance:start -->", "")
            .replace("<!-- finance:end -->", "")
            .strip()
        )
        path.write_text(
            "<!-- finance:start -->\n"
            + charts
            + "\n<!-- finance:end -->\n\nMy commentary.\n"
        )
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("<!-- finance:", self.note())
        self.assertTrue(self.note().endswith("My commentary.\n"))

    def test_preserves_commentary_and_skips_identical_writes(self):
        self.assertEqual(self.run_sync().returncode, 0)
        path = self.vault / "Finance dashboard.md"
        path.write_text(self.note() + "\nMy commentary.\n")
        before = path.stat().st_mtime_ns
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("unchanged", result.stdout)
        self.assertEqual(path.stat().st_mtime_ns, before)
        self.assertTrue(self.note().endswith("My commentary.\n"))

    def test_removes_empty_exporter_boilerplate(self):
        self.assertEqual(self.run_sync().returncode, 0)
        path = self.vault / "Finance dashboard.md"
        path.write_text(
            "# Finance dashboard\n\n" + self.note().strip() + "\n\n## Notes\n"
        )
        self.assertEqual(self.run_sync().returncode, 0)
        self.assertNotIn("# Finance dashboard", self.note())
        self.assertNotIn("## Notes", self.note())

    def test_system_category_preserves_existing_properties(self):
        self.assertEqual(self.run_sync().returncode, 0)
        path = self.vault / "Finance dashboard.md"
        body = re.sub(r"\A---\n.*?\n---\n", "", self.note(), count=1, flags=re.DOTALL)
        path.write_text(
            '---\ncategories: ["[[Other]]"]\naliases: ["Money"]\n---\n' + body
        )
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('"[[System]]"', self.note())
        self.assertIn('"[[Other]]"', self.note())
        self.assertIn('aliases: ["Money"]', self.note())

    def test_unpriced_holdings_preserve_the_last_valid_note(self):
        self.assertEqual(self.run_sync().returncode, 0)
        before = self.note()
        with self.entries.open("a") as output:
            output.write(
                "\n2025-03-03 Unknown\n    assets:unknown  1 MISSING\n    equity:opening\n"
            )
        self.assertNotEqual(self.run_sync().returncode, 0)
        self.assertEqual(self.note(), before)

    def test_does_not_overwrite_an_unmanaged_note(self):
        path = self.vault / "Finance dashboard.md"
        path.write_text("My existing note.\n")
        self.assertNotEqual(self.run_sync().returncode, 0)
        self.assertEqual(self.note(), "My existing note.\n")

    def test_empty_journal(self):
        self.entries.write_text("")
        result = self.run_sync("--as-of", "2025-01-01")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("0.00 SEK", self.note())
        self.assertEqual(self.note().count("```mermaid"), 1)


if __name__ == "__main__":
    unittest.main()
