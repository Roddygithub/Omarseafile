# Développement locale

Ce dépôt est un plugin Omarchy/Quickshell écrit en QML/JavaScript.
Lire `README.md`, `CONTRIBUTING.md` et les notes API/sécurité pertinentes
avant les changements concernés.
`PANEL_AUDIT.md` et `docs/PHASE*.md` sont des notes historiques; vérifier
leur contenu dans le code actuel avant de s'y fier.

## Workflow

- Changer le code, puis exécuter `rtk bash scripts/validate.sh`.
- La validation couvre le manifeste, les invariants de sécurité, la cohérence
  des raccourcis, et les suites de tests portables (sans Omarchy/Quickshell).
- `rtk ./deploy.sh --check` confirme que le dépôt et l'installation sont
  synchronisés. Déployer uniquement sur demande explicite.
- Ne pas déployer sans demande séparée.

## Tests

- Tests portables (exécutés dans `validate.sh`): `scripts/test_portable.py`
  et les suites listées dedans.
- Tests locaux (nécessitent qs/Omarchy): `scripts/test_open_lifecycle.py`,
  `scripts/test_connection_service.py`,
  `scripts/test_runtime_remediation.py`, `scripts/test_http_integration.py`.

## Ici, les tests échouent si le contrat est brisé

Ce projet ne masque pas les échecs. Si le validateur échoue, la cause
réelle est corrigée, pas le check.

## Ici, on ne nettoie pas les notes quand elles aident

On peut laisser des notes locales dans `scripts/` si elles expliquent une
décision 개발의 어려운 부분.
