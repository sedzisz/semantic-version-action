# 🚀 Semantic Version GitHub Action

The **Semantic Version Action** is a lightweight, reliable, and reusable GitHub Action for calculating the next semantic version (`MAJOR.MINOR.PATCH`) based on commit messages, branch names, or pull-request labels.

This action allows you to centralize versioning logic in a single repository, keeping your project workflows clean, maintainable, and consistent.

---

## ✨ Features

- **Multiple detection modes**:
    - Commit messages (`[feature] Add X`, `fix: adjust Y`)
    - Branch names (`feature/add-login`, `bugfix/login-error`)
    - Pull request labels (e.g., `breaking`, `feature`, `bug`)
- **Configurable mapping**: Define your own change-type → version-increment rules
- **Flexible outputs**:
    - `version` – e.g. `v1.4.2`
    - `release_needed` – `true` or `false`
    - `release_id` – e.g. `1.4.2` (without `v` prefix)
- **Docker-based**: Runs in an isolated container for consistency across environments
- **Git integration**: Automatically reads existing tags to determine the last version

---

## 📥 Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `type` | Yes | `label` | Detection mode: `commit`, `branch`, or `label` |
| `map` | Yes | See below | JSON mapping of change tokens to bump types |

### Default `map` value:
```json
{
  "major": ["breaking"],
  "minor": ["feature"],
  "patch": ["fix", "bug", "docs"]
}
```

---

## 📤 Outputs

| Output | Description | Example |
|--------|-------------|---------|
| `version` | Computed semantic version with `v` prefix | `v1.4.2` |
| `release_needed` | Whether a new release should be created | `true` |
| `release_id` | Version number without `v` prefix | `1.4.2` |

---

## 📦 Usage

### Method 1: Repository Action (Recommended ✅)

This method is recommended as it supports multi-line JSON and uses defaults from `action.yml`.

#### Basic usage with defaults:
```yaml
- name: Determine next version
  id: version
  uses: sedzisz/semantic-version-action@v1
  with:
    type: label
```

#### With inline JSON:
```yaml
- name: Determine next version
  id: version
  uses: sedzisz/semantic-version-action@v1
  with:
    type: label
    map: '{"major":["breaking"],"minor":["feature"],"patch":["fix","bug","docs"]}'
```

#### With multi-line JSON (more readable):
```yaml
- name: Determine next version
  id: version
  uses: sedzisz/semantic-version-action@v1
  with:
    type: label
    map: |
      {
        "major": ["breaking"],
        "minor": ["feature", "enhancement"],
        "patch": ["fix", "bug", "docs", "chore"]
      }
```

### Method 2: Docker Image

Use this method when you need a specific image version or want to bypass GitHub Actions cache.

```yaml
- name: Determine next version
  id: version
  uses: docker://ghcr.io/sedzisz/semantic-version-action:latest
  env:
    INPUT_TYPE: label
    INPUT_MAP: '{"major":["breaking"],"minor":["feature"],"patch":["fix","bug","docs"]}'
```

⚠️ **Note**: When using `docker://`, you must:
- Use `env:` instead of `with:`
- Prefix variables with `INPUT_`
- Use single-line JSON only (no multi-line with `|`)

---

## 📋 Complete Workflow Example

```yaml
name: Version and Release

on:
  pull_request:
    types: [closed]
    branches:
      - main

jobs:
  release:
    if: github.event.pull_request.merged == true
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Fetch all history for tags

      - name: Determine next version
        id: version
        uses: sedzisz/semantic-version-action@v1
        with:
          type: label
          map: |
            {
              "major": ["breaking", "major"],
              "minor": ["feature", "enhancement"],
              "patch": ["fix", "bug", "docs", "chore"]
            }

      - name: Print version info
        run: |
          echo "Version: ${{ steps.version.outputs.version }}"
          echo "Release needed: ${{ steps.version.outputs.release_needed }}"
          echo "Release ID: ${{ steps.version.outputs.release_id }}"

      - name: Create Git tag
        if: steps.version.outputs.release_needed == 'true'
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git tag ${{ steps.version.outputs.version }}
          git push origin ${{ steps.version.outputs.version }}

      - name: Create GitHub Release
        if: steps.version.outputs.release_needed == 'true'
        uses: actions/create-release@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          tag_name: ${{ steps.version.outputs.version }}
          release_name: Release ${{ steps.version.outputs.version }}
          draft: false
          prerelease: false
```

---

## 🎯 Detection Modes

### Mode: `label` (Recommended for PRs)

Reads the first label from the pull request.

**Example labels**: `breaking`, `feature`, `bug`, `fix`

**PR Requirements**:
- PR must have at least one label
- Only the first label is used for detection

**Workflow**:
```yaml
- uses: sedzisz/semantic-version-action@v1
  with:
    type: label
```

### Mode: `commit`

Extracts change type from the last commit message prefix.

**Supported formats**:
- `[type] message` → e.g., `[feature] Add login page`
- `type: message` → e.g., `fix: Resolve login bug`

**Workflow**:
```yaml
- uses: sedzisz/semantic-version-action@v1
  with:
    type: commit
```

### Mode: `branch`

Extracts change type from the branch name prefix.

**Format**: `type/description` → e.g., `feature/add-auth`, `fix/login-error`

**Workflow**:
```yaml
- uses: sedzisz/semantic-version-action@v1
  with:
    type: branch
```

---

## 🔧 Customizing the Version Map

The `map` input allows you to define custom mappings between change tokens and version bumps.

### Example: Custom tokens
```yaml
map: |
  {
    "major": ["breaking", "breaking-change", "major"],
    "minor": ["feature", "feat", "enhancement", "minor"],
    "patch": ["fix", "bugfix", "hotfix", "patch", "docs", "chore", "refactor"]
  }
```

### Example: Single token per bump type
```yaml
map: '{"major":["BREAKING"],"minor":["FEATURE"],"patch":["FIX"]}'
```

---

## 🧪 Testing Locally

You can test the action locally using Docker:

```bash
# Build the image
docker build -t semantic-version-action .

# Run with test inputs
docker run --rm \
  -e INPUT_TYPE=label \
  -e INPUT_MAP='{"major":["breaking"],"minor":["feature"],"patch":["fix"]}' \
  -e INPUT_LABELS="feature" \
  -v $(pwd):/github/workspace \
  -e GITHUB_OUTPUT=/tmp/output \
  semantic-version-action

# Check outputs
cat /tmp/output
```

---

## 🐛 Troubleshooting

### No version is generated

**Possible causes**:
1. No matching token found in commit/branch/labels
2. No previous version tags exist (will default to `0.0.0`)
3. Token doesn't match any key in the `map`

**Solution**: Check logs for detection messages:
```
[timestamp] Detected token from labels: feature
[timestamp] Mapping returned none for token: xyz. No bump.
```

### Invalid JSON error

**Error**: `Error: MAP is not valid JSON`

**Solution**: Ensure your JSON is properly formatted:
- Use double quotes for keys and string values
- No trailing commas
- For `docker://` method, use single-line JSON only

### Outputs are empty

**Possible causes**:
1. Missing `id:` on the action step
2. Using `docker://` with `with:` instead of `env:`

**Solution**:
```yaml
# ✅ Correct
- id: version  # <-- Don't forget this!
  uses: sedzisz/semantic-version-action@v1
  with:
    type: label

# ✅ For docker:// use env:
- id: version
  uses: docker://ghcr.io/sedzisz/semantic-version-action:latest
  env:
    INPUT_TYPE: label
    INPUT_MAP: '...'
```

---

## 📊 Comparison: Repository vs Docker

| Feature | `uses: repo@tag` | `uses: docker://image` |
|---------|------------------|------------------------|
| Input syntax | `with:` ✅ | `env:` only |
| Multi-line JSON | ✅ Supported | ❌ Not supported |
| Default values | ✅ From `action.yml` | ❌ Must specify all |
| Caching | ✅ Cached by GitHub | ⚠️ May not cache |
| Versioning | ✅ Easy (git tags) | ⚠️ Requires image tags |
| **Recommended** | ✅ **Yes** | For testing only |

---

## 🤝 Contributing

Contributions, issues, and feature requests are welcome!

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## ⭐ Show your support

Give a ⭐️ if this project helped you!
