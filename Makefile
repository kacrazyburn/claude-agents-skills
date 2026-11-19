# Single source of "how we do it": pinning and building the engine, rendering the copies, ops targets.
# The three files under customer/ and worker/ are byte copies of what the engine renders at ENGINE_REF;
# never edit them by hand — `make sync` rewrites them, `make parity` checks them (and the README lines).
#
# The engine repo is private: its location comes only from ENGINE_GIT (env or command line, a path or
# URL), there is no default. The engine is cloned into ENGINE_DIR; the maintainer's own checkout of the
# engine is never touched. Node is not installed on the host: rendering runs in the NODE_IMAGE container.
#
# Through make any failed recipe exits with 2; the case is told apart by the stderr marker:
# `parity: <path> differs`, `parity: README.md lacks line`, `ENGINE_GIT is not set`.

SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := lint
# From a git hook (pre-commit → make lint) git exports repo-local variables: without unexport
# `git -C $(ENGINE_DIR) …` would act on this repo instead of the engine clone.
unexport GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES \
         GIT_COMMON_DIR GIT_NAMESPACE

# --- Engine pin. ENGINE_REF = the engine SHA deployed on the pool server (source of truth for copies).
ENGINE_REF ?= e9b2d972774d0108cbbbc3b0e9d81cba59219d95
ENGINE_DIR ?= $(CURDIR)/.tools/engine
# = NODE_IMAGE of the engine.
NODE_IMAGE ?= node:22.23.4-bookworm-slim
PUBLIC_URL ?= https://92-63-110-49.sslip.io
COPIES := customer/.claude/skills/sdlc-customer/SKILL.md \
          customer/.claude/agents/sdlc-proxy.md \
          worker/.claude/skills/pool-worker/SKILL.md
# make -n runs recipe lines containing $(MAKE): without the guard a dry run of `engine` would stamp
# an unbuilt clone.
DRY_RUN := $(findstring n,$(firstword -$(MAKEFLAGS)))

# Without -i/-t: docker must not read the recipe's stdin and must not emit CRLF. Read-only mounts,
# no network. ENGINE_DIR outside CURDIR is mounted at the same absolute path.
RUN_NODE = docker run --rm --network none -u $$(id -u):$$(id -g) -e HOME=/tmp \
  -e ENGINE_DIR=$(ENGINE_DIR) -e PUBLIC_URL=$(PUBLIC_URL) \
  -v $(CURDIR):$(CURDIR):ro -w $(CURDIR) \
  $(if $(filter $(CURDIR)/%,$(ENGINE_DIR)),,-v $(ENGINE_DIR):$(ENGINE_DIR):ro) \
  $(NODE_IMAGE) node scripts/render.mjs

# --- pre-commit: if it is not on PATH — a pinned zipapp in .tools/ verified by sha256.
PRE_COMMIT_VERSION ?= 4.7.0
PRE_COMMIT_SHA256 ?= 393488513aed286d7a5a978a1fe79b2f5a8802927242a2d241ff10c1a8e8c885
PRE_COMMIT_PYZ := .tools/pre-commit-$(PRE_COMMIT_VERSION).pyz
PRE_COMMIT_URL := https://github.com/pre-commit/pre-commit/releases/download/v$(PRE_COMMIT_VERSION)/pre-commit-$(PRE_COMMIT_VERSION).pyz
PRE_COMMIT_NATIVE := $(shell command -v pre-commit 2>/dev/null)
PRE_COMMIT := $(if $(PRE_COMMIT_NATIVE),pre-commit,python3 $(CURDIR)/$(PRE_COMMIT_PYZ))

FORMATTED := README.md Makefile .gitignore .pre-commit-config.yaml scripts/render.mjs

.PHONY: engine sync parity lint format test test-unit test-integration test-e2e init hooks up down \
        local-depends

# Idempotent by the stamp $(ENGINE_DIR)/.sdlc-built (= full SHA of ENGINE_REF, so an abbreviated
# ENGINE_REF does not force a rebuild). Full clone with --no-local (no
# hardlinks/alternates into someone else's checkout); the pinned SHA is fetched explicitly, so it need
# not be reachable from a branch of ENGINE_GIT. Nothing on stdout.
engine:
	if [ -z '$(ENGINE_GIT)' ]; then \
	  echo 'engine: ENGINE_GIT is not set (path or URL of the engine repo)' >&2; exit 2; \
	fi
	$(if $(DRY_RUN),echo 'engine: skipped under make -n' >&2; exit 0;) \
	want='$(ENGINE_REF)'; \
	if [ -d '$(ENGINE_DIR)/.git' ]; then \
	  want="$$(git -C '$(ENGINE_DIR)' rev-parse -q --verify '$(ENGINE_REF)^{commit}' 2>/dev/null || echo '$(ENGINE_REF)')"; \
	fi; \
	if [ "$$(cat '$(ENGINE_DIR)/.sdlc-built' 2>/dev/null || true)" = "$$want" ]; then exit 0; fi; \
	if [ ! -d '$(ENGINE_DIR)/.git' ]; then \
	  mkdir -p '$(dir $(ENGINE_DIR))'; \
	  git clone -q --no-local --no-checkout '$(ENGINE_GIT)' '$(ENGINE_DIR)' >&2; \
	fi; \
	git -C '$(ENGINE_DIR)' fetch -q origin '$(ENGINE_REF)' >&2; \
	git -C '$(ENGINE_DIR)' checkout -q --detach '$(ENGINE_REF)' >&2; \
	rm -f '$(ENGINE_DIR)/.sdlc-built'; \
	$(MAKE) -C '$(ENGINE_DIR)' MAKEFLAGS= install build >&2; \
	git -C '$(ENGINE_DIR)' rev-parse HEAD > '$(ENGINE_DIR)/.sdlc-built'

# Rewrite the copies with the engine render at ENGINE_REF (R5): render to a temp file in .scratch/,
# then mv over the copy. A failed render leaves the copy untouched and no stray file behind.
sync: engine
	mkdir -p .scratch
	t="$$(mktemp $(CURDIR)/.scratch/sync.XXXXXX)"; trap 'rm -f "$$t"' EXIT; rc=0; \
	for f in $(COPIES); do \
	  if ! $(RUN_NODE) "$$f" > "$$t"; then echo "sync: render failed for $$f" >&2; rc=1; continue; fi; \
	  mkdir -p "$$(dirname "$$f")"; \
	  chmod 644 "$$t"; mv "$$t" "$$f"; \
	done; \
	exit "$$rc"

# Compare every copy with the render and check that README carries every engine line (R4, R8).
# All mismatches and render failures are reported, no early exit.
parity: engine
	mkdir -p .scratch
	t="$$(mktemp $(CURDIR)/.scratch/parity.XXXXXX)"; trap 'rm -f "$$t"' EXIT; rc=0; \
	for f in $(COPIES); do \
	  if ! $(RUN_NODE) "$$f" > "$$t"; then echo "parity: render failed for $$f" >&2; rc=1; continue; fi; \
	  if ! diff -u "$$f" "$$t" >&2; then \
	    echo "parity: $$f differs from engine render at $(ENGINE_REF)" >&2; rc=1; \
	  fi; \
	done; \
	if ! $(RUN_NODE) readme-lines > "$$t"; then \
	  echo 'parity: render failed for readme-lines' >&2; rc=1; \
	else \
	  while IFS= read -r line; do \
	    if ! grep -F -x -e "$$line" README.md > /dev/null; then \
	      echo "parity: README.md lacks line: $$line" >&2; rc=1; \
	    fi; \
	  done < "$$t"; \
	fi; \
	if [ "$$rc" = 0 ]; then echo 'parity: OK (ENGINE_REF $(ENGINE_REF))'; fi; \
	exit "$$rc"

# Static checks, no engine and no docker.
lint:
	rc=0; \
	for f in $(COPIES); do \
	  if [ ! -f "$$f" ]; then echo "lint: $$f is missing" >&2; rc=1; continue; fi; \
	  if [ "$$(head -n 1 "$$f")" != '---' ]; then echo "lint: $$f does not start with ---" >&2; rc=1; fi; \
	  case "$$f" in \
	    */SKILL.md) want="$$(basename "$$(dirname "$$f")")" ;; \
	    *) want="$$(basename "$$f" .md)" ;; \
	  esac; \
	  got="$$(awk 'NR == 1 { next } /^---$$/ { exit } /^name:/ { sub(/^name:[ ]*/, ""); print; exit }' "$$f")"; \
	  if [ "$$got" != "$$want" ]; then echo "lint: $$f frontmatter name '$$got' != '$$want'" >&2; rc=1; fi; \
	done; \
	for f in $(COPIES) $(FORMATTED); do \
	  if [ -f "$$f" ] && grep -l $$'\r' "$$f" > /dev/null; then echo "lint: $$f has CR line endings" >&2; rc=1; fi; \
	done; \
	if [ -n "$$(git ls-files .github/workflows)" ]; then echo 'lint: .github/workflows must not exist' >&2; rc=1; fi; \
	exit "$$rc"

# Trailing whitespace and the final newline; the engine copies are excluded (byte copies).
format:
	for f in $(FORMATTED); do \
	  [ -f "$$f" ] || continue; \
	  sed -i -E 's/[[:space:]]+$$//' "$$f"; \
	  if [ -s "$$f" ] && [ -n "$$(tail -c 1 "$$f")" ]; then printf '\n' >> "$$f"; fi; \
	done

test:
	$(MAKE) -s --no-print-directory parity

# No code of our own: the unit level is the static lint, the integration level is the engine parity.
test-unit:
	$(MAKE) -s --no-print-directory lint

test-integration:
	$(MAKE) -s --no-print-directory parity

test-e2e:
	echo 'n/a: no services (static skills repo)'

init: hooks

hooks:
ifeq ($(PRE_COMMIT_NATIVE),)
	mkdir -p .tools
	if [ ! -f "$(PRE_COMMIT_PYZ)" ]; then \
	  curl -fsSL -o "$(PRE_COMMIT_PYZ).tmp" "$(PRE_COMMIT_URL)"; \
	  if ! echo "$(PRE_COMMIT_SHA256)  $(PRE_COMMIT_PYZ).tmp" | sha256sum -c --quiet -; then \
	    rm -f "$(PRE_COMMIT_PYZ).tmp"; \
	    echo "pre-commit zipapp: sha256 mismatch, refusing to run it" >&2; \
	    exit 1; \
	  fi; \
	  mv "$(PRE_COMMIT_PYZ).tmp" "$(PRE_COMMIT_PYZ)"; \
	fi
	echo "$(PRE_COMMIT_SHA256)  $(PRE_COMMIT_PYZ)" | sha256sum -c --quiet -
endif
	$(PRE_COMMIT) install -f

up down local-depends:
	echo 'n/a: no services (static skills repo)'
