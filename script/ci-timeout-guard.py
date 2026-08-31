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
# L'indentation sous `jobs:` n'est pas imposee par YAML : deux espaces est
# l'usage, quatre est accepte par GitHub. Le motif se construit sur ce que le
# fichier utilise vraiment, sinon aucun job n'est vu et tout passe au vert.
JOB_KEY_TEMPLATE = r"^{indent}([A-Za-z0-9_-]+):[ \t]*(#.*)?$"
TIMEOUT_RE = re.compile(r"^([ \t]*)timeout-minutes:[ \t]*(\S+)")
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

    first_body = next(
        (l for l in lines[jobs_at + 1:] if l.strip() and not l.lstrip().startswith("#")),
        None,
    )
    if first_body is None:
        return problems

    indent = first_body[: len(first_body) - len(first_body.lstrip())]
    if not indent:
        return [f"{path}: bloc `jobs:` dont les entrees ne sont pas indentees"]

    job_key_re = re.compile(JOB_KEY_TEMPLATE.format(indent=re.escape(indent)))

    starts = [n for n in range(jobs_at + 1, len(lines)) if job_key_re.match(lines[n])]
    # Un `jobs:` sans job reconnu veut dire que l'analyse a echoue, pas que le
    # fichier est sain. C'est le mode de defaillance le plus dangereux ici :
    # silencieux et vert.
    if not starts:
        return [f"{path}: bloc `jobs:` present mais aucun job reconnu — analyse a revoir"]

    for i, start in enumerate(starts):
        end = starts[i + 1] if i + 1 < len(starts) else len(lines)
        body = lines[start:end]
        name = job_key_re.match(lines[start]).group(1)
        where = f"{path}:{start + 1} (job `{name}`)"

        if any(USES_WORKFLOW_RE.match(l) for l in body):
            continue
        if not any(RUNS_ON_RE.match(l) for l in body):
            continue

        # Seul un `timeout-minutes` au niveau du job borne le job. Le meme mot
        # sous une etape ne borne que l'etape : le job continue de tourner, et
        # c'est exactement l'incident des 19-20 aout.
        key_indent = min(
            (len(l) - len(l.lstrip()) for l in body[1:] if l.strip() and not l.lstrip().startswith("#")),
            default=None,
        )
        found = next(
            (
                m
                for l in body
                if (m := TIMEOUT_RE.match(l)) and len(m.group(1)) == key_indent
            ),
            None,
        )
        if not found:
            problems.append(f"{where} : pas de `timeout-minutes` au niveau du job, donc 6 h et 2,16 $ s'il se fige")
            continue

        raw = found.group(2)
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
