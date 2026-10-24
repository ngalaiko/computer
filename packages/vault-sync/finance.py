#!/usr/bin/env python3
"""Generate a Ledger dashboard for Obsidian's native Pele renderer."""

import argparse
import csv
from datetime import date, datetime, timedelta
from decimal import Decimal, ROUND_CEILING, ROUND_FLOOR
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import uuid
from zoneinfo import ZoneInfo

ROOTS = ("assets", "liabilities", "equity", "revenue", "expenses")
COLORS = {
    "assets": "#356e9b",
    "liabilities": "#b74045",
    "equity": "#735295",
    "revenue": "#397b45",
    "expenses": "#b8601d",
    "up": "#397b45",
    "down": "#b74045",
    "flat": "#69717a",
}
PALETTE = ["#356e9b", "#397b45", "#735295", "#b8601d", "#287c7d", "#946d1b"]
CATEGORY_COLORS = {
    "cash": "#356e9b",
    "investments": "#397b45",
    "pension": "#735295",
    "savings": "#287c7d",
    "receivables": "#b8601d",
    "crypto": "#946d1b",
    "funds": "#356e9b",
    "stocks": "#397b45",
    "certificates": "#946d1b",
    "Taxes": "#b74045",
    "Food": "#397b45",
    "Rent": "#356e9b",
}
LEGACY_START = "<!-- finance:start -->"
LEGACY_END = "<!-- finance:end -->"
CHARTS = re.compile(r"```mermaid\n.*?```", re.DOTALL)
FORMAT = "%(quoted(account)),%(quoted(quantity(scrub(display_total)))),%(quoted(commodity(scrub(display_total))))\n"


def chart_text(value):
    return json.dumps(value.replace('"', "″"), ensure_ascii=False)


def money(value, signed=False):
    return format(value, "+,.2f" if signed else ",.2f").replace(",", " ")


def month_start(day, offset=0):
    year, month = divmod(day.year * 12 + day.month - 1 + offset, 12)
    return date(year, month + 1, 1)


def balances(journal, roots, end, currency, begin=None, depth=1, flat=False):
    valuation_date = "date" if begin else f"[{end - timedelta(days=1)}]"
    accounts = [pattern for root in roots for pattern in (f"^{root}:", f"^{root}$")]
    output_format = FORMAT.replace("display_total", "amount") if flat else FORMAT
    command = [
        "ledger",
        "--args-only",
        "--file",
        str(journal),
        "--price-db",
        os.devnull,
        "balance",
        *accounts,
        "--end",
        end.isoformat(),
        "--limit",
        "account !~ /:aktiebolag(:|$)/",
        "--amount",
        f'market(amount, {valuation_date}, "{currency}")',
        *(["--flat"] if flat else ["--depth", str(depth)]),
        "--no-total",
        "--format",
        output_format,
    ]
    if begin:
        command.extend(["--begin", begin.isoformat()])
    result = subprocess.run(
        command, cwd=journal.parent, capture_output=True, text=True, timeout=120
    )
    if result.returncode:
        raise ValueError(f"Ledger report failed: {result.stderr.strip()}")
    values = {}
    for row in csv.reader(io.StringIO(result.stdout), escapechar="\\"):
        if len(row) != 3:
            raise ValueError("Unexpected Ledger report format")
        account, number, commodity = row
        amount = Decimal(number)
        if not amount.is_finite() or (amount and commodity != currency):
            raise ValueError(
                f"Cannot value {account} in {currency}; check journal prices"
            )
        values[account] = amount
    return values


def root_total(values, root):
    return values.get(
        root,
        sum(
            (
                v
                for a, v in values.items()
                if a.startswith(root + ":") and a.count(":") == 1
            ),
            Decimal(0),
        ),
    )


def category_totals(values, root):
    groups = {
        a: v
        for a, v in values.items()
        if a.startswith(root + ":") and a.count(":") == 1
    }
    remainder = root_total(values, root) - sum(groups.values(), Decimal(0))
    if abs(remainder) >= Decimal("0.005"):
        groups[root] = remainder
    return groups


def titled_chart(chart, title):
    if not chart:
        return ""
    return chart.replace(
        "```mermaid\n",
        "```mermaid\n---\ntitle: " + json.dumps(title, ensure_ascii=False) + "\n---\n",
        1,
    )


def net_worth_chart(history, currency):
    values = [value for _, value in history]
    margin = max((max(values) - min(values)) / 10, Decimal(1))
    lower = (min(values) - margin).to_integral_value(rounding=ROUND_FLOOR)
    upper = (max(values) + margin).to_integral_value(rounding=ROUND_CEILING)
    labels = [day.strftime("%b") for day, _ in history[:-1]] + ["Today"]
    return "\n".join(
        [
            "```mermaid",
            "xychart-beta",
            f'    title "Net worth · {money(values[-1])} {currency} · {history[-1][0]}"',
            "    x-axis [" + ", ".join(json.dumps(label) for label in labels) + "]",
            f'    y-axis "{currency}" {lower} --> {upper}',
            "    line [" + ", ".join(f"{value:.2f}" for value in values) + "]",
            "```",
        ]
    )


def sankey(activity):
    roots = {root: root_total(activity, root) for root in ROOTS}
    if abs(sum(roots.values(), Decimal(0))) > Decimal("0.01"):
        raise ValueError(
            "Personal postings do not balance; check FX and excluded company accounts"
        )
    roots = {a: v.quantize(Decimal("0.01")) for a, v in roots.items()}
    largest = max(roots, key=lambda a: abs(roots[a]))
    roots[largest] -= sum(roots.values(), Decimal(0))
    credits = -sum(v for v in roots.values() if v < 0)
    if not credits:
        return ""
    funds = "Funds (" + money(credits) + ")"
    edges, colors = [], {funds: COLORS["flat"]}
    for root, amount in roots.items():
        if not amount:
            continue
        label = root + " (" + money(abs(amount)) + ")"
        colors[label] = COLORS[root]
        edges.append((label, funds, -amount) if amount < 0 else (funds, label, amount))
    data = io.StringIO()
    writer = csv.writer(data, lineterminator="", quoting=csv.QUOTE_ALL)
    for source, target, value in edges:
        writer.writerow([source, target])
        data.write(f",{value:.2f}\n")
    config = {
        "sankey": {
            "showValues": False,
            "linkColor": "gradient",
            "nodeColors": colors,
            "width": 900,
            "height": 350,
            "useMaxWidth": True,
        }
    }
    return (
        "```mermaid\n%%{init: "
        + json.dumps(config)
        + "}%%\nsankey-beta\n\n"
        + data.getvalue()
        + "```"
    )


def investment_names(values):
    grouped = {}
    for account, value in values.items():
        name = account.rsplit(":", 1)[-1]
        grouped[name] = grouped.get(name, Decimal(0)) + value
    return grouped


def investment_revaluation(current, opening, flows):
    end, start, postings = map(investment_names, (current, opening, flows))
    return {
        name: end.get(name, Decimal(0))
        - start.get(name, Decimal(0))
        - postings.get(name, Decimal(0))
        for name in end.keys() | start.keys() | postings.keys()
    }


def investment_tree(investments):
    holdings = {}
    for account, value in investments.items():
        path = account.removeprefix("assets:investments:").split(":")
        category = path[0] if len(path) > 1 else "Other"
        bucket = holdings.setdefault(category, {})
        bucket[path[-1]] = bucket.get(path[-1], Decimal(0)) + value
    return holdings


def signed_tree(values):
    return {
        side: {
            a: v for a, v in values.items() if (v > 0 if side == "debits" else v < 0)
        }
        for side in ("debits", "credits")
    }


def tree_change(tree, changes):
    return sum(
        (
            tree_change(child, changes)
            if isinstance(child, dict)
            else changes.get(name, Decimal(0))
            if child >= Decimal("0.005")
            else Decimal(0)
            for name, child in tree.items()
        ),
        Decimal(0),
    )


def treemap(tree, root, changes=None, signed=False):
    def total(node):
        return (
            sum((total(child) for child in node.values()), Decimal(0))
            if isinstance(node, dict)
            else (abs(node) if signed else max(node, Decimal(0)))
        )

    def net(node):
        return (
            sum((net(child) for child in node.values()), Decimal(0))
            if isinstance(node, dict)
            else node
        )

    styles = {}

    def style(color):
        if color not in styles:
            styles[color] = "c" + str(len(styles))
        return ":::" + styles[color]

    def render(node, level, inherited):
        lines = []
        for index, (name, child) in enumerate(
            sorted(node.items(), key=lambda item: (-total(item[1]), item[0]))
        ):
            amount = total(child)
            if amount < Decimal("0.005"):
                continue
            shown = net(child) if signed else amount
            label = f"{name} · {money(shown)}"
            color = CATEGORY_COLORS.get(name, PALETTE[index % len(PALETTE)])
            if name == "debits":
                color = (
                    COLORS["up"]
                    if root == "liabilities"
                    else COLORS.get(root, inherited)
                )
            elif name == "credits" or shown < 0:
                color = COLORS["down"]
            if changes is not None:
                change = (
                    tree_change(child, changes)
                    if isinstance(child, dict)
                    else changes.get(name, Decimal(0))
                )
                label += " · Δ " + money(change, signed=True)
            if not isinstance(child, dict) and changes is not None:
                color = (
                    COLORS["up"]
                    if change >= Decimal("0.005")
                    else COLORS["down"]
                    if change <= Decimal("-0.005")
                    else COLORS["flat"]
                )
            line = "    " * level + chart_text(label)
            line += "" if isinstance(child, dict) else f": {amount:.2f}"
            lines.append(line + style(color))
            if isinstance(child, dict):
                lines.extend(render(child, level + 1, color))
        return lines

    if total(tree) < Decimal("0.005"):
        return ""
    label = f"{root} · " + ("net " + money(net(tree)) if signed else money(total(tree)))
    if changes is not None:
        label += " · Δ " + money(tree_change(tree, changes), signed=True)
    body = [
        chart_text(label) + style(COLORS.get(root, PALETTE[0])),
        *render(tree, 1, COLORS.get(root, PALETTE[0])),
    ]
    classes = [
        f"classDef {name} fill:{color},color:#fff,stroke:{color};"
        for color, name in styles.items()
    ]
    config = {"treemap": {"showValues": False, "nodeWidth": 100, "nodeHeight": 60}}
    return "\n".join(
        [
            "```mermaid",
            "%%{init: " + json.dumps(config) + "}%%",
            "treemap-beta",
            *body,
            *classes,
            "```",
        ]
    )


def dashboard(journal, as_of, months, currency):
    end = as_of + timedelta(days=1)
    begin = as_of - timedelta(days=29)
    current = balances(journal, ["assets", "liabilities"], end, currency, depth=2)
    total = root_total(current, "assets") + root_total(current, "liabilities")
    groups = category_totals(current, "assets")
    activity = balances(journal, ROOTS, end, currency, begin=begin, depth=2)
    expenses = {
        a.removeprefix("expenses:"): v
        for a, v in category_totals(activity, "expenses").items()
    }
    investments = balances(journal, ["assets:investments"], end, currency, flat=True)
    opening = balances(journal, ["assets:investments"], begin, currency, flat=True)
    flows = balances(
        journal, ["assets:investments"], end, currency, begin=begin, flat=True
    )
    history = []
    for offset in range(-months, 0):
        next_month = month_start(as_of, offset + 1)
        holdings = balances(journal, ["assets", "liabilities"], next_month, currency)
        history.append(
            (
                next_month - timedelta(days=1),
                root_total(holdings, "assets") + root_total(holdings, "liabilities"),
            )
        )
    history.append((as_of, total))
    dates = f"{begin} – {as_of}"
    assets_title = (
        "Assets (positive balances)"
        if any(
            v <= Decimal("-0.005") for v in [*groups.values(), *investments.values()]
        )
        else "Assets"
    )
    if abs(
        sum(investments.values(), Decimal(0))
        - groups.get("assets:investments", Decimal(0))
    ) > Decimal("0.01"):
        raise ValueError("Investment holdings do not match the assets balance")
    liabilities = {
        a.removeprefix("liabilities:"): v
        for a, v in category_totals(current, "liabilities").items()
    }
    changes = investment_revaluation(investments, opening, flows)
    positions = investment_tree(investments)
    investment_delta = money(tree_change(positions, changes), signed=True)
    charts = [
        titled_chart(sankey(activity), f"Last 30 days · {dates} · {currency}"),
        titled_chart(
            treemap(signed_tree(expenses), "expenses", signed=True),
            f"Expenses · last 30 days · {dates} · {currency}",
        ),
        net_worth_chart(history, currency),
        titled_chart(
            treemap(
                {a.removeprefix("assets:"): v for a, v in groups.items()}, "assets"
            ),
            f"{assets_title} · {as_of} · {currency}",
        ),
        titled_chart(
            treemap(positions, "investments", changes),
            f"Investments · Δ {investment_delta} {currency} · Price + FX (30d) · {as_of}",
        ),
        titled_chart(
            treemap(signed_tree(liabilities), "liabilities", signed=True),
            f"Liabilities · {as_of} · {currency}",
        ),
    ]
    return "\n\n".join(filter(None, charts))


def split_frontmatter(text):
    match = re.match(r"\A---\n(.*?)\n---\n?", text, re.DOTALL)
    return (match[1], text[match.end() :]) if match else ("", text)


def system_header(header):
    lines = header.splitlines()
    start = next(
        (i for i, line in enumerate(lines) if line.startswith("categories:")), None
    )
    if start is None:
        lines.extend(["categories:", '  - "[[System]]"'])
    else:
        end = start + 1
        while end < len(lines) and (
            lines[end].startswith((" ", "\t")) or not lines[end].strip()
        ):
            end += 1
        block = "\n".join(lines[start:end])
        if "[[System]]" not in block:
            rest = lines[start].split(":", 1)[1].strip()
            if not rest:
                lines.insert(start + 1, '  - "[[System]]"')
            else:
                try:
                    values = json.loads(rest)
                except json.JSONDecodeError:
                    values = rest.strip("\"'")
                if not isinstance(values, list):
                    values = [values]
                lines[start:end] = [
                    "categories:",
                    *[
                        "  - " + json.dumps(value, ensure_ascii=False)
                        for value in [*values, "[[System]]"]
                    ],
                ]
    return "---\n" + "\n".join(lines) + "\n---\n\n"


def update_note(path, section):
    if path.is_symlink():
        raise ValueError("Dashboard must not be a symlink")
    old = path.read_text() if path.exists() else ""
    header, body = split_frontmatter(old)
    if LEGACY_START in body or LEGACY_END in body:
        if (
            body.count(LEGACY_START) != 1
            or body.count(LEGACY_END) != 1
            or body.index(LEGACY_END) < body.index(LEGACY_START)
        ):
            raise ValueError("Invalid legacy dashboard markers")
        outside = (
            body[: body.index(LEGACY_START)]
            + body[body.index(LEGACY_END) + len(LEGACY_END) :]
        )
    else:
        managed = [
            match
            for match in CHARTS.finditer(body)
            if re.search(
                r'(?:^|\n)(?:    title |title: )"(?:Total|Net worth|Last 30 days|Allocation|Assets|Expenses|Investments|Liabilities)',
                match[0],
            )
        ]
        if body.strip() and not managed:
            raise ValueError("Dashboard contains no managed charts")
        pieces, cursor = [], 0
        for match in managed:
            pieces.append(body[cursor : match.start()])
            cursor = match.end()
        pieces.append(body[cursor:])
        outside = "".join(pieces)
    outside = re.sub(r"\A# Finance dashboard\n+", "", outside)
    outside = re.sub(r"\n+## Notes\n*\Z", "", outside).strip("\n")
    new = (
        system_header(header)
        + section
        + "\n"
        + ("\n" + outside + "\n" if outside.strip() else "")
    )
    if new == old:
        return False
    temporary = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    try:
        # Normal creation mode preserves the vault's default sharing ACLs.
        with open(
            os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o666), "w"
        ) as output:
            output.write(new)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--ledger-file",
        default=os.environ.get(
            "LEDGER_FILE",
            str(
                Path(os.environ.get("FINANCE_DIR", "/home/nikita/finance"))
                / "main.ledger"
            ),
        ),
    )
    parser.add_argument(
        "--vault", default=os.environ.get("OBSIDIAN_VAULT_DIR", "/home/nikita/Vault")
    )
    parser.add_argument(
        "--as-of",
        type=date.fromisoformat,
        default=datetime.now(ZoneInfo("Europe/Stockholm")).date(),
    )
    parser.add_argument("--months", type=int, default=12)
    parser.add_argument("--currency", default="SEK")
    args = parser.parse_args()
    if not 1 <= args.months <= 120 or not re.fullmatch("[A-Z]{3}", args.currency):
        parser.error("months must be 1–120; currency must be a three-letter code")
    try:
        section = dashboard(
            Path(args.ledger_file).resolve(), args.as_of, args.months, args.currency
        )
        changed = update_note(Path(args.vault) / "Finance dashboard.md", section)
    except (OSError, ValueError, ArithmeticError, subprocess.SubprocessError) as error:
        print(f"finance: {error}", file=sys.stderr)
        return 1
    print("finance: dashboard " + ("updated" if changed else "unchanged"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
