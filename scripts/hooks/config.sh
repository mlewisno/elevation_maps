#!/usr/bin/env bash
#
# config.sh - Per-project validator configuration
#
# Copy this file to your project's scripts/hooks/ directory
# and customize as needed.

# Which validators to run on pre-commit (fast, per-commit checks)
# Available: branch-protect diff-size-check single-concern-check ruby rails-frontend
PRE_COMMIT_VALIDATORS=(branch-protect diff-size-check single-concern-check adr-check python)

# Which validators to run on pre-push (full-project checks)
# Available: spec-check ruby-full security coverage-check twelve-factor-check skill-lint config-check context-bloat ruby-validators dirty-check rails-frontend readme-check python python-security
VALIDATORS=(skill-lint config-check context-bloat dirty-check readme-check python python-security)

# Commit message validation (runs on commit-msg hook)
COMMIT_LINT_ENABLED=true

# Diff size limit (production code lines)
DIFF_LIMIT=150

# Allow [large] override tag
ALLOW_LARGE_OVERRIDE=true

# Single-concern thresholds
FILE_COUNT_THRESHOLD=5
DIR_SPREAD_THRESHOLD=2

# Ruby-specific settings (if using ruby validator)
RUBOCOP_ENABLED=true
RSPEC_ENABLED=true
RSPEC_FAIL_FAST=true

# Python-specific settings (if using python validator)
BLACK_ENABLED=true
MYPY_ENABLED=true
PYTEST_ENABLED=true

# Go-specific settings (if using go validator)
GOFMT_ENABLED=true
GOVET_ENABLED=true
GOTEST_ENABLED=true

# TypeScript-specific settings (if using typescript validator)
PRETTIER_ENABLED=true
ESLINT_ENABLED=true
TSCCHECK_ENABLED=true

# Rails frontend (JS/CSS) settings (if using rails-frontend validator)
RAILS_FRONTEND_ENABLED=true        # Enable Rails frontend validation
RAILS_FRONTEND_BLOCKING=true       # If true, fails push on lint errors
ESLINT_AUTOFIX=false               # Auto-fix ESLint issues (not recommended in hooks)
STYLELINT_ENABLED=true             # Enable Stylelint for CSS/SCSS
STYLELINT_AUTOFIX=false            # Auto-fix Stylelint issues (not recommended in hooks)

# Security scanning settings (if using security validator)
BRAKEMAN_ENABLED=true
BUNDLER_AUDIT_ENABLED=true
IMPORTMAP_AUDIT_ENABLED=true

# Spec-check settings (if using spec-check validator)
SPEC_CHECK_ENABLED=true
SPEC_REQUIRE_ISSUE_REF=false  # If true, blocks commits without refs
SPEC_WARN_ON_DRAFT=true       # Warn when spec is still in Draft status

# ADR-check settings (if using adr-check validator)
ADR_CHECK_ENABLED=true        # Warn on dependency changes or decision language

# Coverage settings (if using coverage-check validator)
COVERAGE_ENABLED=true           # Enable coverage checking
COVERAGE_BLOCKING=false         # If true, fails push on low coverage
COVERAGE_MIN_THRESHOLD=80       # Minimum overall coverage percentage
UNDERCOVER_ENABLED=false        # Use Undercover for diff-aware coverage
UNDERCOVER_COMPARE_BRANCH=main  # Branch to compare against for Undercover

# Twelve-Factor compliance settings (if using twelve-factor-check validator)
TWELVE_FACTOR_ENABLED=true      # Enable 12-factor compliance checking

# Individual factor checks
TF_DEPENDENCIES_ENABLED=true    # Factor 2: Lockfile checks
TF_CONFIG_ENABLED=true          # Factor 3: Secret/config detection
TF_LOGS_ENABLED=true            # Factor 11: Log file detection
TF_PARITY_ENABLED=true          # Factor 10: Env branching

# Blocking behavior
TF_SECRETS_BLOCKING=true        # Block on detected secrets
TF_LOCKFILE_BLOCKING=true       # Block on missing lockfiles
TF_CONFIG_BLOCKING=false        # Advisory for config issues
TF_LOGS_BLOCKING=false          # Advisory for log issues
TF_PARITY_BLOCKING=false        # Advisory for parity issues

# Skill lint settings (if using skill-lint validator)
SKILL_LINT_ENABLED=true         # Enable skill file linting
SKILL_BLOCKING=false            # If true, fails on skill lint errors
SKILL_MAX_INLINE_COMMANDS=3     # Warn if more than N complex inline commands
SKILL_MAX_COMMAND_LENGTH=80     # Warn if command line exceeds N chars

# Config check settings (if using config-check validator)
CONFIG_CHECK_ENABLED=true       # Enable config consistency checking
CONFIG_CHECK_BLOCKING=true      # If true, fails on JSON syntax errors

# Context bloat settings (if using context-bloat validator)
CONTEXT_BLOAT_ENABLED=true      # Enable context bloat detection
CONTEXT_BLOAT_BLOCKING=false    # If true, fails on bloat detection
SKILL_LINE_LIMIT=500            # Max lines per skill file
RULE_LINE_LIMIT=300             # Max lines per rule file
MAX_NESTING_DEPTH=3             # Max directory nesting in .claude/

# Ruby validators settings (if using ruby-validators validator)
RUBY_VALIDATORS_ENABLED=true    # Enable Ruby validator test suite
RUBY_VALIDATORS_BLOCKING=true   # If true, fails push on test failures

# Dirty check settings (if using dirty-check validator)
DIRTY_CHECK_ENABLED=true        # Warn about uncommitted changes before push

# README freshness settings (if using readme-check validator)
README_CHECK_ENABLED=true       # Enable README freshness checking
README_CHECK_BLOCKING=false     # If true, fails push on stale README

# Branch protection settings (if using branch-protect validator)
PROTECTED_BRANCHES=(main master) # Branches that block direct commits
