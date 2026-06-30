---
description: WP Pro Max natural-language router — describe what you want and I'll route to the right command, skill, or agent.
argument-hint: "<what you want to do>"
allowed-tools: [Read, Bash, Glob, Grep, Task, Skill]
---

# /wp-pro-max

Natural-language entry point for WP Pro Max. Classifies your request and dispatches
to the appropriate command, skill, or agent.

## Usage

```bash
/wp-pro-max "build a site from ./examples/sample-site"
/wp-pro-max "check status"
/wp-pro-max "audit accessibility"
/wp-pro-max "convert to a block theme"
/wp-pro-max "seed the team members"
/wp-pro-max "ship to production"
/wp-pro-max "fix the header template"
```

## Procedure

```bash
set -e
source "${CLAUDE_PLUGIN_ROOT}/scripts/wp-pro-max-router-lib.sh"

REQUEST="${ARGUMENTS:-}"

if [ -z "$REQUEST" ]; then
  wpm_route_print_help
  if [ -f "./wp-build.json" ]; then
    source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"
    echo ""
    wpbuild_status 2>/dev/null || true
  fi
  exit 0
fi

INPUT_FILE="$(wpm_route_prepare_input "$REQUEST")"
ROUTE_FILE="$WPM_ROUTE_FILE"

# 1. Classify the request via a lightweight subagent.
Task(
  subagent_type="coder",
  description="Classify WP Pro Max request",
  prompt="You are a request classifier for WP Pro Max. Read the JSON at ${INPUT_FILE} (contains request + pwd). Classify into exactly one target from this allowlist: commands[build,status,env,init,plugin,a11y-audit,figma,component,site-editor]; skills[html-analysis,html-optimization,theme-conversion,plugin-selection,wp-scaffold,content-seeding,plugin-data-seeding,wp-i18n,wp-seo,wp-security,wp-qa,wp-ship,wp-handoff,wp-env-setup,section-redesign,content-enrichment,pre-conversion-qa]; agents[wp-theme-developer,wp-data-engineer,wp-deployer,wp-plugin-developer,a11y-checker,figma-analyzer]. Write JSON to ${ROUTE_FILE}: {\"target_type\":\"command|skill|agent|unknown\",\"target\":\"<slug>\",\"args\":\"<remaining args>\",\"reason\":\"<one line>\"}. Guidance: build/convert/create site → command build; status/progress → status; local env → env; scaffold → init; plugin dev → plugin; accessibility audit → a11y-audit; Figma → figma or figma-analyzer; component → component; redesign/enrich/check optimized HTML → site-editor; skill-specific → matching skill; theme/template work → wp-theme-developer; data/seed/DB → wp-data-engineer; deploy/ship/rollback → wp-deployer; plugin code → wp-plugin-developer; unclear → unknown. Return only the path to ${ROUTE_FILE}."
)

# 2. Validate the classifier output.
wpm_route_validate "$ROUTE_FILE" >/dev/null

TARGET_TYPE="$(jq -r '.target_type' "$ROUTE_FILE")"
TARGET="$(jq -r '.target' "$ROUTE_FILE")"
ARGS="$(jq -r '.args // ""' "$ROUTE_FILE")"
REASON="$(jq -r '.reason // ""' "$ROUTE_FILE")"

echo "Detected intent: $REASON"
echo "Routing to $TARGET_TYPE '$TARGET'"

# 3. Dispatch to the selected command, skill, or agent.
case "$TARGET_TYPE" in
  command)
    case "$TARGET" in
      build) Skill(name="wp-pro-max:build", arguments="$ARGS") ;;
      status) Skill(name="wp-pro-max:status", arguments="$ARGS") ;;
      env) Skill(name="wp-pro-max:env", arguments="$ARGS") ;;
      init) Skill(name="wp-pro-max:init", arguments="$ARGS") ;;
      plugin) Skill(name="wp-pro-max:plugin", arguments="$ARGS") ;;
      a11y-audit) Skill(name="wp-pro-max:a11y-audit", arguments="${ARGS:-all}") ;;
      figma) Skill(name="wp-pro-max:figma", arguments="$ARGS") ;;
      component) Skill(name="wp-pro-max:component", arguments="$ARGS") ;;
      site-editor) Skill(name="wp-pro-max:site-editor", arguments="$ARGS") ;;
      *) echo "wp-pro-max: unknown command '$TARGET'" >&2; exit 1 ;;
    esac
    ;;
  skill)
    case "$TARGET" in
      html-analysis|html-optimization|theme-conversion|plugin-selection|wp-scaffold|content-seeding|plugin-data-seeding|wp-i18n|wp-seo|wp-security|wp-qa|wp-ship|wp-handoff|wp-env-setup|section-redesign|content-enrichment|pre-conversion-qa)
        Skill(name="wp-pro-max:$TARGET", arguments="$ARGS") ;;
      *) echo "wp-pro-max: unknown skill '$TARGET'" >&2; exit 1 ;;
    esac
    ;;
  agent)
    case "$TARGET" in
      wp-theme-developer|wp-data-engineer|wp-deployer|wp-plugin-developer|a11y-checker|figma-analyzer)
        # Escape inner double quotes so the prompt string stays intact.
        ARGS_ESCAPED="${ARGS//\"/\\\"}"
        Task(
          subagent_type="coder",
          description="WP Pro Max agent dispatch: $TARGET",
          prompt="You are the $TARGET agent for WP Pro Max. The user said: \"$ARGS_ESCAPED\". Working directory: $(pwd). Read the relevant manifest (wp-build.json or wp-plugin.json) for context, follow your agent instructions in ${CLAUDE_PLUGIN_ROOT}/agents/${TARGET}.md, and do the work. Report what you did and the result."
        ) ;;
      *) echo "wp-pro-max: unknown agent '$TARGET'" >&2; exit 1 ;;
    esac
    ;;
  unknown|*)
    echo "wp-pro-max: I couldn't confidently route this request." >&2
    echo "Reason: $REASON" >&2
    echo "Try one of: build, status, env, init, plugin, a11y-audit, figma, component, site-editor, or name a specific skill/agent." >&2
    exit 1
    ;;
esac
```
