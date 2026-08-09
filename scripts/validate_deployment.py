#!/usr/bin/env python3
"""
Validate a deployment directory before Terraform ever sees it.

Run by both CI (plan.yml) and the agent locally. Keeping it in one script
means the agent's local check and the CI gate cannot drift apart.

Usage:
    python3 scripts/validate_deployment.py deployments/dev/demo
    python3 scripts/validate_deployment.py --all
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

try:
    from jsonschema import Draft202012Validator
except ImportError:
    sys.exit("Missing dependency. Run: pip install jsonschema")

REPO_ROOT = Path(__file__).resolve().parent.parent
SCHEMA_PATH = REPO_ROOT / "schemas" / "app-stack.schema.json"

REQUIRED_FILES = ["terraform.tfvars.json", "backend.hcl", "main.tf", "variables.tf"]


def fail(deployment: Path, message: str) -> str:
    return f"  [FAIL] {deployment}: {message}"


def validate(deployment: Path, validator: Draft202012Validator) -> list[str]:
    errors: list[str] = []

    for filename in REQUIRED_FILES:
        if not (deployment / filename).is_file():
            errors.append(fail(deployment, f"missing required file '{filename}'"))
    if errors:
        return errors

    tfvars_path = deployment / "terraform.tfvars.json"
    try:
        tfvars = json.loads(tfvars_path.read_text())
    except json.JSONDecodeError as exc:
        return [fail(deployment, f"terraform.tfvars.json is not valid JSON: {exc}")]

    for error in sorted(validator.iter_errors(tfvars), key=lambda e: list(e.path)):
        location = ".".join(str(p) for p in error.path) or "(root)"
        errors.append(fail(deployment, f"{location}: {error.message}"))

    # The directory name is the deployment identity. A mismatch would put
    # state and resources under different names, which is very confusing to
    # unpick later.
    if tfvars.get("name") != deployment.name:
        errors.append(
            fail(
                deployment,
                f"name '{tfvars.get('name')}' does not match directory name '{deployment.name}'",
            )
        )

    expected_env = deployment.parent.name
    if tfvars.get("environment") != expected_env:
        errors.append(
            fail(
                deployment,
                f"environment '{tfvars.get('environment')}' does not match parent directory '{expected_env}'",
            )
        )

    # backend.hcl must point at a state key derived from the same identity,
    # or two deployments could silently share state.
    backend = (deployment / "backend.hcl").read_text()
    expected_key = f"{expected_env}/{deployment.name}.tfstate"
    if not re.search(rf'^\s*key\s*=\s*"{re.escape(expected_key)}"\s*$', backend, re.M):
        errors.append(
            fail(deployment, f'backend.hcl must set: key = "{expected_key}"')
        )

    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("deployments", nargs="*", help="deployment directories")
    parser.add_argument("--all", action="store_true", help="validate every deployment")
    args = parser.parse_args()

    schema = json.loads(SCHEMA_PATH.read_text())
    Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schema)

    if args.all:
        targets = sorted(p.parent for p in REPO_ROOT.glob("deployments/*/*/terraform.tfvars.json"))
    else:
        targets = [Path(d).resolve() for d in args.deployments]

    if not targets:
        print("No deployments to validate.")
        return 0

    all_errors: list[str] = []
    for deployment in targets:
        errors = validate(deployment, validator)
        if errors:
            all_errors.extend(errors)
        else:
            print(f"  [ok]   {deployment.relative_to(REPO_ROOT)}")

    if all_errors:
        print("\nValidation failed:\n")
        print("\n".join(all_errors))
        print(
            "\nFix the tfvars file to satisfy schemas/app-stack.schema.json. "
            "Do not work around this by editing the schema."
        )
        return 1

    print("\nAll deployments valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
