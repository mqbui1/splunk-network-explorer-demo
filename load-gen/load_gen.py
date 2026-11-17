"""
Travel planner load generator for the eBPF network monitoring demo.

Sends continuous POST /plan requests to the orchestrator to generate
steady-state APM traces and network flow data. Rotates destinations
so the service map shows varied traffic patterns.

Usage:
    python3 load_gen.py --url http://localhost:8080/plan --rps 1
    python3 load_gen.py --url http://localhost:8080/plan --rps 3 --verbose
"""
import argparse
import itertools
import sys
import time
from datetime import datetime

import requests

ORIGINS = ["Seattle", "New York", "London", "Tokyo", "Sydney"]
DESTINATIONS = ["Paris", "Tokyo", "Rome", "London", "New York", "Sydney"]
TRAVELLERS = [1, 2, 2, 3]   # weighted toward 2

ROUTES = list(itertools.product(ORIGINS, DESTINATIONS))
# Remove same-city routes
ROUTES = [(o, d) for o, d in ROUTES if o.lower() != d.lower()]


def run(url: str, rps: float, verbose: bool) -> None:
    interval = 1.0 / rps
    route_cycle = itertools.cycle(ROUTES)
    traveller_cycle = itertools.cycle(TRAVELLERS)

    total = 0
    errors = 0

    print(f"Load generator started — {rps} req/s → {url}")
    print("Ctrl+C to stop\n")

    try:
        while True:
            origin, destination = next(route_cycle)
            travellers = next(traveller_cycle)

            payload = {
                "origin": origin,
                "destination": destination,
                "travellers": travellers,
            }

            start = time.monotonic()
            status = "?"
            try:
                resp = requests.post(url, json=payload, timeout=15)
                elapsed_ms = (time.monotonic() - start) * 1000
                status = resp.status_code
                total += 1

                if resp.status_code != 200:
                    errors += 1

                if verbose:
                    print(
                        f"[{datetime.now().strftime('%H:%M:%S')}] "
                        f"{origin:12} -> {destination:12} "
                        f"HTTP {status} {elapsed_ms:6.0f}ms"
                    )
                elif total % 10 == 0:
                    err_rate = errors / total * 100
                    print(
                        f"[{datetime.now().strftime('%H:%M:%S')}] "
                        f"sent={total} errors={errors} ({err_rate:.1f}%) "
                        f"last={elapsed_ms:.0f}ms HTTP{status}"
                    )

            except requests.exceptions.Timeout:
                elapsed_ms = (time.monotonic() - start) * 1000
                errors += 1
                total += 1
                print(
                    f"[{datetime.now().strftime('%H:%M:%S')}] "
                    f"TIMEOUT {origin} -> {destination} ({elapsed_ms:.0f}ms)"
                )
            except requests.exceptions.ConnectionError as exc:
                errors += 1
                total += 1
                print(
                    f"[{datetime.now().strftime('%H:%M:%S')}] "
                    f"CONNECTION ERROR: {exc}"
                )

            # Sleep to maintain target RPS, accounting for request duration
            elapsed = time.monotonic() - start
            sleep_time = max(0.0, interval - elapsed)
            time.sleep(sleep_time)

    except KeyboardInterrupt:
        print(f"\nStopped. Total: {total}, Errors: {errors}")
        sys.exit(0)


def main() -> None:
    parser = argparse.ArgumentParser(description="Travel planner load generator")
    parser.add_argument(
        "--url",
        default="http://localhost:8080/plan",
        help="Orchestrator /plan endpoint URL",
    )
    parser.add_argument(
        "--rps",
        type=float,
        default=1.0,
        help="Requests per second (default: 1.0)",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print every request (default: print every 10)",
    )
    args = parser.parse_args()
    run(args.url, args.rps, args.verbose)


if __name__ == "__main__":
    main()
