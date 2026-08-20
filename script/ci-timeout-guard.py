#!/usr/bin/env python3
"""Refuse un workflow dont un job n'a pas de `timeout-minutes`.

Un job sans timeout explicite tourne jusqu'au plafond de 6 h de GitHub, et
chaque minute est facturee. Les 19 et 20 aout 2026, seize jobs se sont figes
sur l'etape `apt-get` de deux depots : 5 834 minutes, 35 $. Le meme incident sur
un runner macOS en debut de mois avait coute 67 $. Aucun de ces jobs n'avait de
`timeout-minutes` — GitHub applique alors 360 minutes par defaut.

Ce garde-fou echoue si un seul job du depot repasse dans cet etat. Il ne depend
que de la bibliotheque standard : il tourne en premiere etape, avant toute
installation, pour que la CI casse en deux secondes et pas en six heures.

    python3 script/ci-timeout-guard.py [--max N] [chemin ...]

Analyse ligne a ligne, pas de PyYAML : c'est le prix de « zero dependance, des
la premiere etape ». Le format vise est celui que GitHub impose de toute facon
(cle de job indentee de deux espaces sous `jobs:`).
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

JOBS_RE = re.compile(r"^jobs:[ \t]*(#.*)?$")
JOB_KEY_RE = re.compile(r"^  ([A-Za-z0-9_-]+):[ \t]*(#.*)?$")
TIMEOUT_RE = re.compile(r"^\s+timeout-minutes:[ \t]*(\S+)")
# Un job qui delegue a un workflow reutilisable ne porte pas son propre
# `runs-on` : le timeout vit dans le workflow appele, pas ici.
USES_WORKFLOW_RE = re.compile(r"^\s+uses:[ \t]*\S+\.ya?ml(@\S+)?[ \t]*$")
RUNS_ON_RE = re.compile(r"^\s+runs-on:")


def audit(path: Path, ceiling: int) -> list[str]:
    lines = path.read_text(encoding="utf-8").splitlines()
    problems: list[str] = []

    jobs_at = next((n for n, l in enumerate(lines) if JOBS_RE.match(l)), None)
    if jobs_at is None:
        return problems

    starts = [n for n in range(jobs_at + 1, len(lines)) if JOB_KEY_RE.match(lines[n])]
    for i, start in enumerate(starts):
        end = starts[i + 1] if i + 1 < len(starts) else len(lines)
        body = lines[start:end]
        name = JOB_KEY_RE.match(lines[start]).group(1)
        where = f"{path}:{start + 1} (job `{name}`)"

        if any(USES_WORKFLOW_RE.match(l) for l in body):
            continue
        if not any(RUNS_ON_RE.match(l) for l in body):
            continue

        found = next((TIMEOUT_RE.match(l) for l in body if TIMEOUT_RE.match(l)), None)
        if not found:
            problems.append(f"{where} : pas de `timeout-minutes`, donc 6 h et 2,16 $ s'il se fige")
            continue

        raw = found.group(1)
        # Une expression `${{ ... }}` est legitime mais illisible ici : on la
        # laisse passer plutot que d'inventer sa valeur.
        if raw.startswith("${{"):
            continue
        try:
            value = int(raw)
        except ValueError:
            problems.append(f"{where} : `timeout-minutes: {raw}` n'est pas un entier")
            continue
        if value > ceiling:
            problems.append(
                f"{where} : `timeout-minutes: {value}` depasse le plafond de {ceiling} min. "
                "Relever le plafond deliberement si le job le merite."
            )
    return problems


def main(argv: list[str]) -> int:
    ceiling = 60
    if "--max" in argv:
        idx = argv.index("--max")
        ceiling = int(argv[idx + 1])
        del argv[idx : idx + 2]

    targets = [Path(a) for a in argv[1:]] or sorted(
        p for p in Path(".github/workflows").glob("*.y*ml")
    )
    if not targets:
        print("Aucun workflow a verifier.")
        return 0

    problems = [p for t in targets for p in audit(t, ceiling)]
    if not problems:
        print(f"{len(targets)} workflow(s) : chaque job est borne.")
        return 0

    for p in problems:
        print(f"::error::{p}")
    print(f"\n{len(problems)} job(s) non borne(s). Voir Hermes : ci_couts_github_actions.md")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
