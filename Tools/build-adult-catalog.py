#!/usr/bin/env python3
"""Rebuild the Adult sites category from a pinned Bon-Appetit/porn-domains snapshot."""
import json
from pathlib import Path
import tempfile
from urllib.request import urlopen

REVISION = "e49b7131ba1e407f240dffc055bb51dfa824cd7a"
BASE = f"https://raw.githubusercontent.com/Bon-Appetit/porn-domains/{REVISION}"
PSL_URL = "https://raw.githubusercontent.com/publicsuffix/list/763a4c200052f4cbc42fc123d2a80ff9437103c7/public_suffix_list.dat"
SECOND_LIST = "https://raw.githubusercontent.com/Sinfonietta/hostfiles/4f7229bea95b8b0116fd3022359b3828ccd022c0/pornography-hosts"
OUTPUT = Path(__file__).resolve().parents[1] / "Shift/Resources/Filtering/WebsiteCategories.json"


def fetch(url):
    with urlopen(url, timeout=60) as response:
        return response.read()


def entries(metadata):
    name = metadata["name"]
    data = fetch(metadata["raw_url"])
    if len(data) != metadata["size"]:
        raise ValueError(f"Unexpected contents of {name}")
    for line in data.decode("utf-8").splitlines():
        host = line.strip().rstrip(".").lower()
        if host and not host.startswith("#"):
            yield host.encode("idna").decode("ascii")


def apply_exceptions(domains):
    # A listing for a hosting service such as blogspot.com cannot classify its tenants.
    exact, wildcard, exceptions = set(), set(), set()
    for line in fetch(PSL_URL).decode("utf-8").splitlines():
        rule = line.strip()
        if not rule or rule.startswith("//"):
            continue
        if rule.startswith("!"):
            exceptions.add(rule[1:].encode("idna").decode("ascii"))
        elif rule.startswith("*."):
            wildcard.add(rule[2:].encode("idna").decode("ascii"))
        else:
            exact.add(rule.encode("idna").decode("ascii"))
    for host in domains:
        base = host.removeprefix("www.")
        labels = base.split(".")
        institutional = labels[-1] in {"gov", "edu", "mil"} or (
            len(labels) >= 2 and len(labels[-1]) == 2 and labels[-2] in {"gov", "gob", "gouv", "edu", "ac"}
        )
        if institutional or base in exact or (base.partition(".")[2] in wildcard and base not in exceptions):
            domains[host] = 0


def main():
    metadata = json.loads(fetch(f"{BASE}/meta.json"))
    domains = dict.fromkeys(entries(metadata["blocklist"]), 1)
    domains.update(dict.fromkeys(entries(metadata["allowlist"]), 0))
    apply_exceptions(domains)
    also_listed = set()
    for line in fetch(SECOND_LIST).decode("utf-8").splitlines():
        fields = line.partition("#")[0].split()
        if len(fields) == 2 and fields[0] == "0.0.0.0":
            also_listed.add(fields[1].lower().rstrip("."))
    if not also_listed:
        raise ValueError("Empty corroborating domain list")
    # An explicit negative www row is needed only if it overrides a positive apex.
    blocked = {host for host, decision in domains.items() if decision and host in also_listed}
    overrides = {host for host in domains if host.startswith("www.") and host[4:] in blocked and host not in blocked}
    categories = json.loads(OUTPUT.read_text(encoding="utf-8"))
    categories["Adult sites"] = sorted(blocked | {"!" + host for host in overrides})
    with tempfile.TemporaryDirectory(dir=OUTPUT.parent) as directory:
        catalog = Path(directory) / OUTPUT.name
        catalog.write_text(json.dumps(categories, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        catalog.replace(OUTPUT)
    print(f"{len(blocked):,} blocked hosts, {len(overrides):,} explicit www exceptions")


if __name__ == "__main__":
    main()
