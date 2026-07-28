#!/usr/bin/env python3
"""Resolve package aliases and build dependency graphs for Repo A.

Usage:
    python scripts/resolve-packages.py [--check-alias NAME]
    python scripts/resolve-packages.py --graph PACKAGE [--depth N]
"""

import argparse
import json
import sys
from collections import deque
from pathlib import Path

CONFIG_DIR = Path(__file__).resolve().parent.parent / "config"
ALIASES_FILE = CONFIG_DIR / "aliases.yaml"
REQUIRED_BINARIES_FILE = CONFIG_DIR / "required-binaries.yaml"
PACKAGES_FILE = CONFIG_DIR / "packages.yaml"
LOCK_FILE = CONFIG_DIR / "termux-lock.json"


def load_yaml_simple(path: Path) -> dict:
    """Load a simple YAML file into a dict (no external deps)."""
    import re

    result = {}
    current_key = None
    current_list = None
    current_dict = None
    current_dict_key = None

    with open(path) as f:
        for line in f:
            stripped = line.rstrip()
            if not stripped or stripped.startswith("#") or stripped.startswith("---"):
                continue

            # List item
            if stripped.startswith("  - ") and current_list is not None:
                current_list.append(stripped[4:].strip())
                continue

            # Key: value
            m = re.match(r"^(\w[\w-]*):\s*(.*)", stripped)
            if m:
                key, val = m.group(1), m.group(2).strip()
                if val == "":
                    # Start a list or dict
                    # Check next lines to determine
                    result[key] = []
                    current_list = result[key]
                    current_key = key
                else:
                    if val.startswith('"') and val.endswith('"'):
                        val = val[1:-1]
                    result[key] = val
                    current_list = None
                continue

            # Nested dict entry
            if stripped.startswith("    ") and current_key and isinstance(result.get(current_key), list):
                # Sub-item in a dict within list
                continue

    return result


def load_yaml(path: Path) -> dict:
    """Load YAML using PyYAML if available, fallback to simple parser."""
    try:
        import yaml

        with open(path) as f:
            return yaml.safe_load(f) or {}
    except ImportError:
        return load_yaml_simple(path)


def validate_aliases(aliases: dict) -> list[str]:
    """Return list of validation errors for alias mappings."""
    errors = []
    for alias, target in aliases.get("aliases", {}).items():
        if not alias.replace("-", "").replace("_", "").isalnum():
            errors.append(f"Invalid alias name: {alias}")
        if not target.replace("-", "").replace("_", "").isalnum():
            errors.append(f"Invalid target name for alias {alias}: {target}")
    return errors


def resolve_alias(aliases: dict, name: str) -> str:
    """Resolve a user-facing name to its canonical build target."""
    return aliases.get("aliases", {}).get(name, name)


def build_dependency_graph(packages: dict) -> dict[str, list[str]]:
    """Build a dependency graph from package definitions."""
    graph = {}
    for pkg_name, pkg_def in packages.get("packages", {}).items():
        deps = pkg_def.get("dependencies", [])
        graph[pkg_name] = deps
    return graph


def resolve_build_order(packages: dict, target: str) -> list[str]:
    """Resolve the build order for a target package using topological sort."""
    graph = build_dependency_graph(packages)

    # Check that target exists
    all_packages = set(packages.get("packages", {}).keys())
    if target not in all_packages and target not in graph:
        raise ValueError(f"Package '{target}' not found in packages.yaml")

    visited = set()
    order = []
    temp_mark = set()

    def visit(node: str):
        if node in visited:
            return
        if node in temp_mark:
            raise ValueError(f"Circular dependency detected involving '{node}'")
        temp_mark.add(node)
        for dep in graph.get(node, []):
            visit(dep)
        temp_mark.remove(node)
        visited.add(node)
        order.append(node)

    visit(target)
    return order


def check_required_binaries(packages: dict, required: list[str]) -> dict[str, bool]:
    """Check which required binaries have providers in the package set."""
    result = {}
    pkg_names = set(packages.get("packages", {}).keys())
    for binary in required:
        # Binary name often matches or starts with a package name
        found = binary in pkg_names or any(
            binary.startswith(pkg) or pkg.startswith(binary)
            for pkg in pkg_names
        )
        result[binary] = found
    return result


def main():
    parser = argparse.ArgumentParser(description="Resolve packages for Repo A")
    parser.add_argument("--check-alias", help="Check if an alias is valid")
    parser.add_argument("--graph", help="Build dependency graph for a package")
    parser.add_argument("--depth", type=int, default=0, help="Max depth for dependency resolution")
    parser.add_argument("--check-binaries", action="store_true", help="Check required binaries coverage")
    parser.add_argument("--json", action="store_true", help="Output JSON format")
    args = parser.parse_args()

    aliases = load_yaml(ALIASES_FILE)
    required = load_yaml(REQUIRED_BINARIES_FILE)
    packages = load_yaml(PACKAGES_FILE)
    lock = json.loads(LOCK_FILE.read_text()) if LOCK_FILE.exists() else {}

    if args.check_alias:
        resolved = resolve_alias(aliases, args.check_alias)
        if args.json:
            print(json.dumps({"input": args.check_alias, "resolved": resolved}))
        else:
            print(f"{args.check_alias} -> {resolved}")
        return 0

    if args.graph:
        try:
            order = resolve_build_order(packages, args.graph)
            if args.json:
                print(json.dumps({"target": args.graph, "build_order": order}))
            else:
                print(f"Build order for {args.graph}:")
                for i, pkg in enumerate(order, 1):
                    print(f"  {i}. {pkg}")
        except ValueError as e:
            print(f"Error: {e}", file=sys.stderr)
            return 1
        return 0

    if args.check_binaries:
        bin_coverage = check_required_binaries(packages, required.get("required_binaries", []))
        if args.json:
            print(json.dumps(bin_coverage, indent=2))
        else:
            for binary, found in bin_coverage.items():
                status = "OK" if found else "MISSING"
                print(f"  {binary}: {status}")
        return 0

    # Default: print alias validation and dependency graph summary
    alias_errors = validate_aliases(aliases)
    if alias_errors:
        print("Alias validation errors:", file=sys.stderr)
        for err in alias_errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    print("Alias validation: OK")
    print(f"Locked termux commit: {lock.get('pinned_termux_commit', 'N/A')}")
    print(f"Registered packages: {len(packages.get('packages', {}))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
