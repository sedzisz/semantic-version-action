# 🚀 Semantic Version GitHub Action

The **Semantic Version Action** is a lightweight, reliable, and reusable GitHub Action for calculating the next semantic version (`MAJOR.MINOR.PATCH`) based on commit messages, branch names, or pull-request labels.

This action allows you to centralize versioning logic in a single repository, keeping your project workflows clean, maintainable, and consistent.

---

## ✨ Features

- Detects change type using:
    - Commit messages (`[feature] Add X`, `fix: adjust Y`)
    - Branch names (`feature/*`)
    - Pull request labels (e.g., `breaking`, `feature`, `bug`)
- Configurable change-type → version-increment mapping
- Outputs:
    - `version` – e.g. `v1.4.2`
    - `release_needed` – whether a release should be created
    - `release_id` – e.g. `1.4.2`
- Runs inside a container for consistency and isolation
- Automatically receives the workspace mounted by GitHub Actions

---

## 📥 Inputs

### `type`
Determines how the change type is extracted.  
Supported values:
- `commit` — reads tokens from commit message prefixes
- `branch` — reads token from the branch name (e.g., `feature/*`)
- `label` — reads change type from pull-request labels

### `map`
A JSON object mapping change tokens to version bump types.  
Example:
```json
{
  "major": ["breaking"],
  "minor": ["feature"],
  "patch": ["fix", "bug", "docs"]
}
```

## 📦 Usage

Add the following to your workflow:

```yaml
jobs:
  versioning:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Determine next version
        id: version
        uses: sedzisz/semantic-version-action@v1
        with:
          type: label
          map: '{"major":["breaking"],"minor":["feature"],"patch":["fix","bug","docs"]}'

      - name: Print results
        run: |
          echo "Version: ${{ steps.version.outputs.version }}"
          echo "Release needed: ${{ steps.version.outputs.release_needed }}"
          echo "Release ID: ${{ steps.version.outputs.release_id }}"
```