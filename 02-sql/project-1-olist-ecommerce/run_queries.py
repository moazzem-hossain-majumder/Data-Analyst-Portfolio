#!/usr/bin/env python3
"""Runs every numbered query (-- Qnn | title) in sql/*.sql and saves each result as results/Qnn_*.csv.
Usage (from the project root):  python run_queries.py [database] [psql-args...]
Example:                        python run_queries.py olist
Needs `psql` on the PATH and the database already built (scripts 01, 02 and 04 run)."""
import re, subprocess, sys, pathlib, csv, io

db = sys.argv[1] if len(sys.argv) > 1 else "olist"
psql_args = sys.argv[2:]
root = pathlib.Path(__file__).parent
out = root / "results"; out.mkdir(exist_ok=True)
pattern = re.compile(r"(?ms)^-- (Q\d+) \| (.+?)\n(.*?)(?=^-- Q\d+ \||\Z)")
count = 0
for f in sorted((root / "sql").glob("0[3-9]_*.sql")) + sorted((root / "sql").glob("1*_*.sql")):
    for qid, title, body in pattern.findall(f.read_text()):
        sql = "\n".join(l for l in body.splitlines() if not l.strip().startswith("--")).strip().rstrip(";")
        if not sql: continue
        cmd = ["psql", *psql_args, "-d", db, "-v", "ON_ERROR_STOP=1", "-q", "-c", "SET search_path TO olist",
               "-c", f"COPY ({sql}) TO STDOUT WITH CSV HEADER"]
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode:
            print(f"FAILED {qid} ({f.name}): {res.stderr.strip()[:300]}"); sys.exit(1)
        slug = re.sub(r"[^a-z0-9]+", "_", title.lower()).strip("_")[:50]
        (out / f"{qid}_{slug}.csv").write_text(res.stdout)
        rows = len(list(csv.reader(io.StringIO(res.stdout)))) - 1
        print(f"{qid}  {rows:>4} rows  {title[:70]}"); count += 1
print(f"done: {count} queries")
