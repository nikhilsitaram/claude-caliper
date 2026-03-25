#!/usr/bin/env python3
"""
Run skill evaluation prompts via claude -p.

For each eval in evals.json, spawns claude -p with the skill loaded as
system prompt. Captures output text and timing data per run.

Usage:
    python run_eval.py \\
      --evals-path .skill-evals/tdd/evals.json \\
      --output-dir .skill-evals/tdd/iteration-1/ \\
      --variant after \\
      --skill-path skills/test-driven-development/SKILL.md \\
      --runs 3

Subprocess environment:
    - CLAUDECODE env var removed (allows nested claude -p)
    - --output-format json (captures timing in response)
    - --allowedTools "" (pure text, no tool use)
    - --no-session-persistence (no session storage overhead)
    - --model sonnet (default, overridable via --model flag)
    - --disable-slash-commands (no slash command discovery)
    - --settings disableAllHooks + empty mcpServers (minimal overhead)
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path


def build_claude_command(
    skill_path: str | None = None, model: str | None = None
) -> list[str]:
    """Build the claude -p command with appropriate flags."""
    cmd = [
        "claude",
        "-p",
        "--output-format",
        "json",
        "--allowedTools",
        "",
        "--no-session-persistence",
        "--model",
        model or "sonnet",
        "--disable-slash-commands",
        "--settings",
        '{"disableAllHooks": true, "mcpServers": {}}',
    ]
    if skill_path:
        content = Path(skill_path).read_text()
        cmd.extend(["--system-prompt", content])
    return cmd


def build_env() -> dict:
    """Build environment for claude -p subprocess.

    Removes CLAUDECODE to allow nested sessions.
    """
    return {k: v for k, v in os.environ.items() if k != "CLAUDECODE"}


def slugify(text: str) -> str:
    """Convert text to URL-safe slug for directory naming."""
    text = text.lower().strip()
    text = re.sub(r"[^\w\s-]", "", text)
    text = re.sub(r"[\s_]+", "-", text)
    return text[:50]


def run_single(cmd: list[str], prompt: str, env: dict, timeout: int = 120) -> dict:
    """Run a single claude -p invocation and return parsed result."""
    try:
        result = subprocess.run(
            cmd,
            input=prompt,
            capture_output=True,
            text=True,
            env=env,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return {
            "result": "",
            "is_error": True,
            "duration_ms": timeout * 1000,
            "cost_usd": 0,
            "num_turns": 0,
            "error": f"Timeout after {timeout}s",
        }

    if result.returncode != 0:
        return {
            "result": result.stdout or "",
            "is_error": True,
            "duration_ms": 0,
            "cost_usd": 0,
            "num_turns": 0,
            "error": result.stderr[:1000] if result.stderr else "Non-zero exit code",
        }

    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        # If JSON parsing fails, treat raw stdout as the result
        return {
            "result": result.stdout,
            "is_error": False,
            "duration_ms": 0,
            "cost_usd": 0,
            "num_turns": 0,
        }


def run_eval(
    evals_path: Path,
    output_dir: Path,
    variant: str,
    skill_path: str | None = None,
    runs: int = 3,
    model: str | None = None,
    timeout: int = 120,
):
    """Run all evals for a single variant."""
    with open(evals_path, encoding="utf-8") as f:
        evals_data = json.load(f)

    cmd = build_claude_command(skill_path, model)
    env = build_env()

    skill_label = Path(skill_path).parent.name if skill_path else "no-skill"
    print(f"\nRunning {len(evals_data['evals'])} evals x {runs} runs [{variant}: {skill_label}]")

    for eval_item in evals_data["evals"]:
        eval_id = eval_item["id"]
        eval_name = eval_item.get("name", f"eval-{eval_id}")
        slug = slugify(eval_name)
        eval_dir_name = f"eval-{eval_id}-{slug}"

        variant_dir = output_dir / eval_dir_name / variant
        variant_dir.mkdir(parents=True, exist_ok=True)

        # Write eval_metadata.json (once per eval, shared across variants)
        # Use exclusive create to avoid races when variants run in parallel
        metadata_path = output_dir / eval_dir_name / "eval_metadata.json"
        try:
            fd = os.open(str(metadata_path), os.O_WRONLY | os.O_CREAT | os.O_EXCL)
            metadata = {
                "eval_id": eval_id,
                "eval_name": eval_name,
                "prompt": eval_item["prompt"],
                "expectations": eval_item.get("expectations", []),
            }
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                json.dump(metadata, f, indent=2)
        except FileExistsError:
            pass  # Another variant already wrote it

        prompt = eval_item["prompt"]

        for run_num in range(1, runs + 1):
            run_dir = variant_dir / f"run-{run_num}"
            run_dir.mkdir(parents=True, exist_ok=True)

            print(f"  [{variant}] {eval_name} run-{run_num}...", end=" ", flush=True)

            start = time.time()
            response = run_single(cmd, prompt, env, timeout)
            wall_time = time.time() - start

            # Write output text
            output_text = response.get("result", "")
            with open(run_dir / "output.txt", "w", encoding="utf-8") as f:
                f.write(output_text)

            # Write timing
            timing = {
                "duration_ms": response.get("duration_ms", 0),
                "wall_time_seconds": round(wall_time, 2),
                "cost_usd": response.get("cost_usd", 0),
                "num_turns": response.get("num_turns", 0),
                "is_error": response.get("is_error", False),
                "total_duration_seconds": round(wall_time, 2),
            }
            if response.get("error"):
                timing["error"] = response["error"]

            with open(run_dir / "timing.json", "w", encoding="utf-8") as f:
                json.dump(timing, f, indent=2)

            status = "ERROR" if response.get("is_error") else "OK"
            print(f"{status} ({wall_time:.1f}s)")

    print(f"\nResults: {output_dir}")


def main():
    parser = argparse.ArgumentParser(
        description="Run skill evaluations via claude -p"
    )
    parser.add_argument(
        "--evals-path", type=Path, required=True, help="Path to evals.json"
    )
    parser.add_argument(
        "--output-dir", type=Path, required=True, help="Output iteration directory"
    )
    parser.add_argument(
        "--variant", required=True, help="Variant name (before/after)"
    )
    parser.add_argument(
        "--skill-path", help="Path to SKILL.md (omit for no-skill baseline)"
    )
    parser.add_argument(
        "--runs", type=int, default=3, help="Runs per eval (default: 3)"
    )
    parser.add_argument(
        "--model", help="Model for eval subject (default: sonnet)"
    )
    parser.add_argument(
        "--timeout", type=int, default=120, help="Timeout per run in seconds"
    )

    args = parser.parse_args()

    if args.runs < 1:
        parser.error("--runs must be >= 1")

    if args.timeout < 1:
        parser.error("--timeout must be >= 1")

    if not args.evals_path.exists():
        print(f"Error: evals file not found: {args.evals_path}")
        sys.exit(1)

    if args.skill_path and not Path(args.skill_path).exists():
        print(f"Error: skill file not found: {args.skill_path}")
        sys.exit(1)

    run_eval(
        evals_path=args.evals_path,
        output_dir=args.output_dir,
        variant=args.variant,
        skill_path=args.skill_path,
        runs=args.runs,
        model=args.model,
        timeout=args.timeout,
    )


if __name__ == "__main__":
    main()
