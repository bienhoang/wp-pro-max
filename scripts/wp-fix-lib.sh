#!/usr/bin/env bash
# wp-fix-lib.sh — argument parsing, finding triage/partition, backup, and manifest
# writes for /wp-pro-max:fix.
#
# Two ways to use it:
#   1) source it:   source "${CLAUDE_PLUGIN_ROOT}/scripts/wp-fix-lib.sh"
#                   then call fix_parse_args / fix_load_findings / fix_backup ...
#   2) sub-command: bash "${CLAUDE_PLUGIN_ROOT}/scripts/wp-fix-lib.sh" load-findings
#
# Sourcing is safe in both bash and zsh: this file does NOT enable `set -e` at the
# top level (that would alter the caller's shell) and avoids shell-reserved names
# such as `status` and `path` (in zsh a local `path` is tied to $PATH).
#
# Requires: jq. Operates on $WP_BUILD_FILE (default: ./wp-build.json).

WP_BUILD_FILE="${WP_BUILD_FILE:-./wp-build.json}"

# Resolve sibling libraries next to this file (bash + zsh).
if [ -n "${BASH_VERSION:-}" ]; then
	_WP_FIX_LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
elif [ -n "${ZSH_VERSION:-}" ]; then
	_WP_FIX_LIB_DIR="$(dirname "${(%):-%x}")"
fi

[ -z "${MANIFEST_LIB_SOURCED:-}" ] && {
	# shellcheck source=manifest-lib.sh
	source "${_WP_FIX_LIB_DIR}/manifest-lib.sh"
	MANIFEST_LIB_SOURCED=1
}
# wp-audit-lib.sh provides audit_wp_env_reachable(). Reuse it; never reimplement
# the probe here — hand-rolling one would put a raw wp-env invocation in this file
# and trip contract-lint Rule 3. audit_wp_env_run() already encapsulates it.
[ -z "${WP_AUDIT_LIB_SOURCED:-}" ] && {
	# shellcheck source=wp-audit-lib.sh
	source "${_WP_FIX_LIB_DIR}/wp-audit-lib.sh"
	WP_AUDIT_LIB_SOURCED=1
}

# -----------------------------------------------------------------------------
# The supported rule set
# -----------------------------------------------------------------------------
# The 9 static PHP rules from scripts/audit-static.sh: the 8 parallel-array rules
# (IDS at :98-107) plus wpcs-missing-nonce (added at :184). These are the only
# findings that carry BOTH a real line number (grep -HnIE at :177) and a
# deterministic pattern, so they are the only ones a diff can be anchored to.
#
# This is an explicit ID list, NOT a category filter, and must stay that way:
# `category` does not track risk. wpcs-output-not-escaped (XSS),
# wpcs-direct-db-no-prepare (SQLi), and wpcs-missing-nonce (CSRF) are all
# category `code-style` (CATS at :111-113). Keying policy on `category` would put
# XSS/SQLi/CSRF on whatever lane `code-style` gets.
FIX_SUPPORTED_RULES_JSON='["sec-eval","sec-unsafe-include","sec-unserialize","sec-file-write-user-input","sec-base64-decode","wpcs-output-not-escaped","wpcs-direct-db-no-prepare","wpcs-missing-sanitize","wpcs-missing-nonce"]'

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------
# Parse the command invocation. MUST be called as: fix_parse_args "$@"
# Never with an unquoted $ARGUMENTS — free-text is multi-word, so word-splitting
# would truncate it and a $( ) in user input would splice into shell syntax.
#
# Sets:
#   FIX_SEVERITY   ""|critical|high|medium|low  (minimum threshold, inclusive)
#   FIX_CATEGORY   ""|security|code-style
#   FIX_DRY_RUN    0|1
#   FIX_FREE_TEXT  positional free-text symptom, joined with spaces
fix_parse_args() {
	FIX_SEVERITY=""
	FIX_CATEGORY=""
	FIX_DRY_RUN=0
	FIX_FREE_TEXT=""

	while [ $# -gt 0 ]; do
		case "$1" in
			--severity)
				[ $# -ge 2 ] || { echo "fix: --severity requires critical|high|medium|low" >&2; return 2; }
				case "$2" in
					critical|high|medium|low) FIX_SEVERITY="$2" ;;
					*) echo "fix: --severity must be critical, high, medium, or low" >&2; return 2 ;;
				esac
				shift 2 ;;
			--category)
				[ $# -ge 2 ] || { echo "fix: --category requires security|code-style" >&2; return 2; }
				# Only the two categories v1 can act on. a11y/performance findings
				# are unsupported (no line anchor), so accepting them here would
				# advertise a run that returns nothing but unsupported[].
				case "$2" in
					security|code-style) FIX_CATEGORY="$2" ;;
					*) echo "fix: --category must be security or code-style (a11y/performance are not fixable in v1)" >&2; return 2 ;;
				esac
				shift 2 ;;
			--dry-run)
				FIX_DRY_RUN=1; shift ;;
			--)
				shift
				while [ $# -gt 0 ]; do
					FIX_FREE_TEXT="${FIX_FREE_TEXT:+${FIX_FREE_TEXT} }$1"
					shift
				done
				break ;;
			-*)
				echo "fix: unknown option $1" >&2; return 2 ;;
			*)
				# Positional free-text symptom. Unlike audit_parse_args (which
				# rejects positionals at wp-audit-lib.sh:52), fix accepts one.
				FIX_FREE_TEXT="${FIX_FREE_TEXT:+${FIX_FREE_TEXT} }$1"
				shift ;;
		esac
	done
}

# -----------------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------------
# The project root that manifest paths are relative to. Defaults to the directory
# holding wp-build.json.
fix_project_root() {
	if [ -n "${FIX_PROJECT_ROOT:-}" ]; then
		printf '%s' "${FIX_PROJECT_ROOT%/}"
		return 0
	fi
	local dir
	dir="$(dirname "$WP_BUILD_FILE")"
	(cd "$dir" 2>/dev/null && pwd) || pwd
}

# fix_rel_path <path> [root] — absolute host path -> repo-relative.
#
# audit-static.sh:41 does ROOT="$(cd "$ROOT" && pwd)", so every `file` in
# audit.findings arrives as an ABSOLUTE host path. Storing it raw would leak
# /Users/<name>/... into a committed wp-build.json and make the Gate 3 diff key
# machine-bound. Non-path values (live findings use a URL or `plugin/<slug>`)
# pass through untouched.
fix_rel_path() {
	local target="${1:?path}" root="${2:-}"
	[ -n "$root" ] || root="$(fix_project_root)"
	root="${root%/}"

	# macOS resolves /var -> /private/var and /tmp -> /private/tmp, so the root and
	# the finding's path can disagree on symlinked ancestors while naming the same
	# file. Compare both spellings of BOTH sides; a missed match here degrades to an
	# absolute path, which leaks /Users/<name> and collapses fix_backup onto a
	# basename (two themes' header.php would overwrite each other's backup).
	local root_phys=""
	root_phys="$(cd "$root" 2>/dev/null && pwd -P)" || root_phys=""

	# Inlined rather than a helper function: a nested function would be global in
	# both bash and zsh, clobbering any same-named function in the caller's shell.
	case "$target" in
		"$root"/*) printf '%s' "${target#"$root"/}"; return 0 ;;
	esac
	if [ -n "$root_phys" ]; then
		case "$target" in
			"$root_phys"/*) printf '%s' "${target#"$root_phys"/}"; return 0 ;;
		esac
	fi

	# Absolute path that matched neither spelling: resolve its own symlinks and
	# retry. Only meaningful for a real path — a URL or `plugin/<slug>` falls
	# straight through untouched.
	case "$target" in
		/*)
			local tdir tbase tphys
			tdir="$(dirname "$target")"; tbase="$(basename "$target")"
			if tphys="$(cd "$tdir" 2>/dev/null && pwd -P)"; then
				tphys="${tphys}/${tbase}"
				case "$tphys" in
					"$root"/*) printf '%s' "${tphys#"$root"/}"; return 0 ;;
				esac
				if [ -n "$root_phys" ]; then
					case "$tphys" in
						"$root_phys"/*) printf '%s' "${tphys#"$root_phys"/}"; return 0 ;;
					esac
				fi
			fi
			;;
	esac

	printf '%s' "$target"
}

# Shared jq `relpath` filter. THE path space of this library is repo-relative —
# `fix.filesChanged` and every `fix.*` path are repo-relative by schema, so every
# producer must emit that spelling. Mixing spellings silently breaks the Gate 3
# diff: an absolute post-scan against a relative baseline shares no keys, so every
# finding reads as both `resolved` AND `new`.
# Callers must pass --arg root / --arg rootp.
FIX_RELPATH_JQ='
	def relpath:
		(. // "" | tostring) as $f
		| if   ($root  != "") and ($f | startswith($root  + "/")) then ($f | ltrimstr($root  + "/"))
		  elif ($rootp != "") and ($f | startswith($rootp + "/")) then ($f | ltrimstr($rootp + "/"))
		  else $f end;
'

# Echo the project root and its physical spelling, for the jq args above.
_fix_roots() {
	FIX_ROOT="$(fix_project_root)"
	FIX_ROOT_PHYS="$(cd "$FIX_ROOT" 2>/dev/null && pwd -P)" || FIX_ROOT_PHYS="$FIX_ROOT"
}

# Resolve the scan scope. It MUST match the scope the baseline audit ran at:
# re-scanning a `--scope all` baseline at `self` narrows the corpus, so every
# finding outside the theme vanishes and reads as "fixed" when nothing was.
fix_resolve_scan_scope() {
	if [ -n "${FIX_SCAN_SCOPE:-}" ]; then printf '%s' "$FIX_SCAN_SCOPE"; return 0; fi
	local s
	s="$(wpbuild_get '.audit.scope // ""' 2>/dev/null)" || s=""
	case "$s" in
		self|all) printf '%s' "$s" ;;
		*)        printf 'self' ;;
	esac
}

# -----------------------------------------------------------------------------
# Finding partition — the core of this library
# -----------------------------------------------------------------------------
# Read audit.findings and split into three buckets:
#   supported   -> the 9 static rules, external:false, line > 0, passing filters
#   skipped     -> supported but filtered out by --severity / --category
#   unsupported -> line == 0 (a11y, every live finding) OR external == true
#                  OR id outside the static rule set
#
# Every unsupported finding carries a `reason` AND a `pointer` to the skill that
# does handle it. They are reported, never silently dropped.
fix_load_findings() {
	_manifest_require_jq || return 1
	[ -f "$WP_BUILD_FILE" ] || { echo "fix_load_findings: $WP_BUILD_FILE not found" >&2; return 1; }

	local root root_phys
	root="$(fix_project_root)"
	root_phys="$(cd "$root" 2>/dev/null && pwd -P)" || root_phys="$root"

	jq -c \
		--argjson rules "$FIX_SUPPORTED_RULES_JSON" \
		--arg minsev "${FIX_SEVERITY:-}" \
		--arg cat "${FIX_CATEGORY:-}" \
		--arg root "$root" \
		--arg rootp "$root_phys" '
		def sev_rank: {"critical":4,"high":3,"medium":2,"low":1,"info":0}[.] // 0;

		# `. // "" | tostring` guards a finding with a missing or non-string `file`:
		# startswith() on null is a hard jq error, which would abort the WHOLE
		# partition rather than routing one malformed finding to unsupported[].
		def relpath:
			(. // "" | tostring) as $f
			| if   ($root  != "") and ($f | startswith($root  + "/")) then ($f | ltrimstr($root  + "/"))
			  elif ($rootp != "") and ($f | startswith($rootp + "/")) then ($f | ltrimstr($rootp + "/"))
			  else $f end;

		# `.id` must be captured before the pipe: inside `$rules | index(...)` the
		# input to index is $rules, so a bare `.id` would index the array.
		def known_rule: (.id // "") as $i | ($rules | index($i)) != null;

		# A finding is fixable only with a real file path, a real line anchor, own
		# code, and a known rule. The file check guards malformed audit input: a
		# finding with line+id but no `file` would otherwise reach supported[] with
		# file:"" and make a later fix_backup "" fail.
		def has_file: ((.file // "") | tostring) != "";

		def is_supported:
			(.external != true)
			and has_file
			and ((.line // 0) > 0)
			and known_rule;

		def passes_filter:
			(($minsev == "") or (((.severity // "info") | sev_rank) >= ($minsev | sev_rank)))
			and (($cat == "") or (.category == $cat));

		# Why this finding is out of scope. Checked most-decisive first: external
		# code is off-limits regardless of what the rule is.
		def reason_of:
			if   .external == true   then "external: true — third-party code"
			elif (has_file | not)    then "no file path — nothing to edit"
			elif ((.line // 0) <= 0) then "no line anchor (line: 0) — nothing to anchor a diff to"
			elif (known_rule | not)  then "id is not one of the 9 supported static PHP rules"
			else "unsupported" end;

		# Where the user should go instead. Never empty.
		def pointer_of:
			if   .external == true then "third-party code — report only; an edit here is reverted by the next update"
			elif (.category == "a11y") then "/wp-pro-max:a11y-audit + the wp-pro-max:accessibility skill"
			elif ((.id // "") | startswith("perf-")) then "the wp-pro-max:wp-performance-backend skill"
			elif ((.id // "") | startswith("sec-live-")) then "update the plugin; the wp-pro-max:wp-security skill"
			elif (.id // "") == "sec-committed-secret" then "rotate the secret, then the wp-pro-max:wp-security skill"
			else "no mechanical fix in v1 — triage by hand" end;

		(.audit.findings // []) as $all
		| {
			supported: [ $all[]
				| select(is_supported) | select(passes_filter)
				| .file = (.file | relpath) ],
			skipped: [ $all[]
				| select(is_supported) | select(passes_filter | not)
				| .file = (.file | relpath) ],
			unsupported: [ $all[]
				| select(is_supported | not)
				| { id, file: (.file | relpath), line: (.line // 0),
				    category, severity, external,
				    reason: reason_of, pointer: pointer_of } ]
		}
	' "$WP_BUILD_FILE"
}

# fix_group_by_file [findings-json] — group supported findings by file, each
# group sorted by line DESCENDING.
#
# Line-descending is load-bearing: fixing line 10 first can change the file's
# line count, which leaves the already-computed line 42 pointing at the wrong
# code. Applying high lines first keeps every lower line valid.
fix_group_by_file() {
	_manifest_require_jq || return 1
	local input="${1:-}"
	if [ -z "$input" ]; then
		input="$(fix_load_findings)" || return 1
	fi
	jq -c '
		(.supported // .)
		| group_by(.file)
		| map({ file: .[0].file, findings: (. | sort_by(.line) | reverse) })
	' <<<"$input"
}

# -----------------------------------------------------------------------------
# Backup — mandatory before any write
# -----------------------------------------------------------------------------
# The repo bar is agents/wp-deployer.md:21 "No backup → no deploy". Same applies
# here: the ability to say "revert that file" requires a snapshot to revert to.

# Initialise a per-run backup directory. Call once per run; sets FIX_BACKUP_DIR.
fix_backup_dir_init() {
	local root ts
	root="$(fix_project_root)"
	ts="$(date -u +%Y%m%dT%H%M%SZ)"
	FIX_BACKUP_DIR="${root}/.wp-fix-backup/${ts}"
	mkdir -p "$FIX_BACKUP_DIR" || return 1
	printf '%s' "$FIX_BACKUP_DIR"
}

# fix_backup <file> [backup-dir] — copy a file into the backup dir BEFORE editing.
# Prints the backup path. Mirrors section_backup() (html-section-lib.sh:69-75) but
# preserves the file's relative directory: wp-fix touches many PHP files and a
# basename-only key would let themes/a/header.php and themes/b/header.php collide,
# silently destroying the first backup.
fix_backup() {
	local file="${1:?file to back up}"
	local dir="${2:-${FIX_BACKUP_DIR:-}}"
	[ -f "$file" ] || { echo "fix_backup: file not found: $file" >&2; return 1; }
	[ -n "$dir" ] || { echo "fix_backup: no backup dir — call fix_backup_dir_init first" >&2; return 1; }

	local rel dest
	rel="$(fix_rel_path "$file")"
	# Never let an absolute or ../ path escape the backup dir.
	case "$rel" in
		/*|../*|*/../*) rel="$(basename "$file")" ;;
	esac
	dest="${dir}/${rel}"
	mkdir -p "$(dirname "$dest")" || return 1
	cp -p "$file" "$dest" || return 1
	printf '%s' "$dest"
}

# fix_restore <file> [backup-dir] — restore a file from its backup.
fix_restore() {
	local file="${1:?file to restore}"
	local dir="${2:-${FIX_BACKUP_DIR:-}}"
	[ -n "$dir" ] || { echo "fix_restore: no backup dir" >&2; return 1; }
	local rel src
	rel="$(fix_rel_path "$file")"
	case "$rel" in
		/*|../*|*/../*) rel="$(basename "$file")" ;;
	esac
	src="${dir}/${rel}"
	[ -f "$src" ] || { echo "fix_restore: no backup for $file at $src" >&2; return 1; }
	cp -p "$src" "$file" || return 1
	printf '%s' "$file"
}

# -----------------------------------------------------------------------------
# Manifest writes
# -----------------------------------------------------------------------------
# fix_record <bucket> <json-object> — append+unique into fix.<bucket>.
# Buckets: addressed | dismissed | remaining | unsupported | filesChanged | runtimeChanges
#
# runtimeChanges entries record the option NAME only, never its value: option
# values hold SMTP/API credentials and wp-build.json is committed. Recording a
# value would inverse secrets-scan.sh:8 ("Never prints the matched secret value").
fix_record() {
	local bucket="${1:?bucket}" json="${2:?json value}"
	case "$bucket" in
		addressed|dismissed|remaining|unsupported|filesChanged|runtimeChanges) ;;
		*) echo "fix_record: unknown bucket '$bucket'" >&2; return 2 ;;
	esac
	_manifest_require_jq || return 1
	[ -f "$WP_BUILD_FILE" ] || { echo "fix_record: $WP_BUILD_FILE not found" >&2; return 1; }

	# --argjson, NOT string interpolation into the jq program. wpbuild_set passes
	# its value to `jq "<path> = (<value>)"`, which EVALUATES it as a jq
	# expression — so an interpolated `$ENV.SECRET` would read the environment
	# into a committed manifest, inverting the names-only secrets rule. --argjson
	# also parses the input as JSON, so malformed values fail here instead of
	# corrupting the file.
	local tmp
	tmp="$(_manifest_tmp)" || return 1
	if ! jq --argjson v "$json" \
		".fix.${bucket} = ((.fix.${bucket} // []) + [\$v] | unique)" \
		"$WP_BUILD_FILE" > "$tmp"; then
		rm -f "$tmp"
		echo "fix_record: invalid JSON for bucket '$bucket' — manifest left untouched" >&2
		return 3
	fi
	mv "$tmp" "$WP_BUILD_FILE"
}

# fix_init <trigger> — stamp fix.generatedAt / fix.trigger / fix.backupDir.
#
# backupDir is stored REPO-RELATIVE. FIX_BACKUP_DIR is absolute because cp needs
# it, but wp-build.json is committed: an absolute path there leaks /Users/<name>
# and points at a directory that does not exist on anyone else's machine.
fix_init() {
	local trigger="${1:?trigger}" ts backup_rel=""
	ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	[ -n "${FIX_BACKUP_DIR:-}" ] && backup_rel="$(fix_rel_path "$FIX_BACKUP_DIR")"
	wpbuild_set '.fix' "((.fix // {}) + $(jq -cn \
		--arg ts "$ts" --arg trigger "$trigger" --arg backup "$backup_rel" \
		'{generatedAt:$ts, trigger:$trigger, verified:false}
		 + (if $backup == "" then {} else {backupDir:$backup} end)'))"
}

# fix_audit_age_warn [max-age-seconds] — warn when audit.generatedAt is stale.
# Stale findings carry stale line numbers: the file may have moved on since the
# scan, so a diff anchored to `line` can land on unrelated code.
fix_audit_age_warn() {
	_manifest_require_jq || return 1
	local max="${1:-86400}" age
	age="$(jq -r --argjson max "$max" '
		(.audit.generatedAt // "") as $g
		| if $g == "" then "none"
		  else (try ((now - ($g | fromdateiso8601)) | floor | tostring) catch "unparsed")
		  end
	' "$WP_BUILD_FILE" 2>/dev/null)" || return 1

	case "$age" in
		none)     echo "fix: no audit.generatedAt — run /wp-pro-max:audit --static first" >&2; return 1 ;;
		unparsed) echo "fix: could not parse audit.generatedAt — treat line numbers as unverified" >&2; return 0 ;;
	esac
	if [ "$age" -gt "$max" ] 2>/dev/null; then
		echo "fix: audit is $((age / 3600))h old — line numbers may be stale. Re-run /wp-pro-max:audit --static to be safe." >&2
		return 0
	fi
	return 0
}

# -----------------------------------------------------------------------------
# Gate 3 — verification by static re-scan
# -----------------------------------------------------------------------------
# Findings that audit-static.sh can actually reproduce. Everything else comes
# from audit-live.sh and can NEVER appear in a static re-scan:
#   perf-*        (audit-live.sh:39)   file is a URL
#   sec-live-*    (audit-live.sh:101)  file is `plugin/<slug>`
#   a11y-axe-*    (audit-live.sh:136)  live DOM only
# If a `mode: live` baseline is diffed unfiltered, every one of those reads as
# "gone" after a static re-scan and the run reports verified:true having fixed
# nothing. Static a11y (`a11y-<rule>`, audit-static.sh:241) IS reproducible, so it
# stays in — a fix that breaks alt text must still be caught.
FIX_STATIC_REPRODUCIBLE_JQ='
	def is_static_reproducible:
		(.id // "") as $i
		| if   ($i | startswith("perf-"))     then false
		  elif ($i | startswith("sec-live-")) then false
		  elif ($i | startswith("a11y-axe-")) then false
		  else true end;
'

# Rules whose CORRECT fix removes the construct the scanner greps for. Only these
# can be expected to disappear from a re-scan.
#
#   sec-eval           — the fix deletes eval(); the pattern `\beval\s*\(` stops matching.
#   wpcs-missing-nonce — an ABSENCE check (audit-static.sh:181-188): it fires when a
#                        file has no check_ajax_referer/wp_verify_nonce. Adding one
#                        clears it.
#
# The other seven are PRESENCE rules: they grep for a risky construct, not for a
# defect, so a correctly fixed line still matches. Verified empirically against
# audit-static.sh — every one of these fires on code that is already correct:
#
#   wpcs-missing-sanitize      `\$_(GET|POST|…)`            matches ANY superglobal read,
#                              so sanitize_text_field(wp_unslash($_GET['q'])) still fires.
#   wpcs-output-not-escaped    `\becho\s+.*\$_(GET|…)`      still fires on
#                              echo esc_html(...$_GET['q']...).
#   wpcs-direct-db-no-prepare  `\$wpdb->query\(.*\$`        still fires on
#                              $wpdb->query($wpdb->prepare(…, %d, $id)).
#   sec-unserialize            `\bunserialize\s*\(`         still fires on
#                              unserialize($d, ['allowed_classes' => false]).
#   sec-base64-decode, sec-unsafe-include, sec-file-write-user-input — same shape.
#
# Requiring these to vanish would report FAILURE on the majority of correct fixes
# and train the user to ignore the gate. They are reported as `stillFlagged`
# (expected), never as a regression.
FIX_CLEARING_RULES_JSON='["sec-eval","wpcs-missing-nonce"]'

# fix_static_rescan <outdir> — re-run audit-static.sh and merge its three output
# files into one {findings:[]} document on stdout.
#
# Returns 0 on a trustworthy scan, 3 on scanner failure. NEVER conflates the two:
# audit-static.sh swallows scanner errors (`|| true` at :232, `|| echo '{}'` at
# :272) and degrades to an empty finding set with exit 0 — indistinguishable from
# a clean scan, and it happens to satisfy "targeted findings gone AND no new
# findings" perfectly. The most likely trigger is our own fix emitting something
# the scanner cannot parse.
fix_static_rescan() {
	local outdir="${1:?outdir}" theme scope
	_fix_roots
	theme="$(wpbuild_get '.theme.path // ""' 2>/dev/null)" || theme=""
	scope="$(fix_resolve_scan_scope)"

	local scanner="${_WP_FIX_LIB_DIR}/audit-static.sh"
	[ -f "$scanner" ] || { echo "fix_static_rescan: scanner not found: $scanner" >&2; return 3; }

	mkdir -p "$outdir" || return 3
	if ! bash "$scanner" "$FIX_ROOT" "$theme" "$scope" "$outdir" >/dev/null 2>&1; then
		echo "fix_static_rescan: audit-static.sh exited non-zero — scan is NOT trustworthy" >&2
		return 3
	fi

	local f
	for f in code-style a11y security; do
		if [ ! -f "${outdir}/${f}.json" ] || ! jq -e '.findings' "${outdir}/${f}.json" >/dev/null 2>&1; then
			echo "fix_static_rescan: ${f}.json missing or unparseable — scan is NOT trustworthy" >&2
			return 3
		fi
	done

	# Relativise on the way out. audit-static.sh:41 resolves ROOT to an absolute
	# host path, so raw scanner output cannot be diffed against a repo-relative
	# baseline or against fix.filesChanged.
	jq -s --arg root "$FIX_ROOT" --arg rootp "$FIX_ROOT_PHYS" \
		"$FIX_RELPATH_JQ"'
		{findings: [ (map(.findings // []) | add)[] | .file = (.file | relpath) ]}
	' "${outdir}/code-style.json" "${outdir}/a11y.json" "${outdir}/security.json" 2>/dev/null \
		|| { echo "fix_static_rescan: could not merge scanner output" >&2; return 3; }
}

# fix_baseline — audit.findings in THE path space (repo-relative), as the Gate 3
# baseline. Emits {findings:[…]}.
fix_baseline() {
	_manifest_require_jq || return 1
	_fix_roots
	jq --arg root "$FIX_ROOT" --arg rootp "$FIX_ROOT_PHYS" \
		"$FIX_RELPATH_JQ"'
		{findings: [ (.audit.findings // [])[] | .file = (.file | relpath) ]}
	' "$WP_BUILD_FILE"
}

# fix_verify <changed-files-json> [workdir] — the ONE Gate 3 entry point.
#
# Wraps baseline → re-scan → diff so a caller cannot mis-wire the three inputs
# (and cannot accidentally mix path spaces). Emits fix_verify_diff's object.
# Returns 3 on scanner failure — which is NEVER a pass.
fix_verify() {
	local changed="${1:-[]}" workdir="${2:-}"
	if [ -z "$workdir" ]; then
		workdir="$(mktemp -d 2>/dev/null)" || { echo "fix_verify: cannot create workdir" >&2; return 3; }
	fi
	mkdir -p "$workdir" || return 3

	local base_file="${workdir}/baseline.json" post_file="${workdir}/post.json"
	fix_baseline > "$base_file" || { echo "fix_verify: could not read the baseline" >&2; return 3; }

	if ! fix_static_rescan "${workdir}/rescan" > "$post_file"; then
		jq -n '{status:"scanner-failed", verified:false,
		        note:"the static re-scan failed — the result is UNVERIFIED. Never report this as success."}'
		return 3
	fi
	fix_verify_diff "$base_file" "$post_file" "$changed"
}

# fix_verify_diff <baseline-json-file> <post-json-file> <changed-files-json>
#
# Set-diff of static findings only. Emits:
#   {status, verified, resolved[], unresolved[], stillFlagged[], stillPresent[], new[], note}
# status: pass | fail | scanner-failed
#
# `verified` means: this run introduced NO regression, AND every finding it
# targeted whose rule can actually clear (FIX_CLEARING_RULES_JSON) did clear.
#
# It deliberately does NOT require presence-rule findings to disappear — they
# cannot. audit-static.sh greps for risky CONSTRUCTS, not for defects, so a
# correctly fixed line still matches (see FIX_CLEARING_RULES_JSON above for the
# empirical per-rule evidence). Requiring them to vanish would fail 7 of the 9
# rules on a correct fix and train the user to ignore the gate. They are reported
# as `stillFlagged` — expected, not a failure.
#
#   resolved[]     targeted, and the finding is gone (a clearing rule did its job)
#   unresolved[]   targeted, clearing rule, STILL matching -> the fix did not work  => FAIL
#   stillFlagged[] targeted, presence rule, still matching  -> expected, informational
#   stillPresent[] in a file this run never touched         -> expected, untouched
#   new[]          appeared or grew                          -> regression => FAIL
#
# Diff key is `id + file` compared by COUNT — lines shift once a fix lands, so a
# line-exact key would report phantom churn. A same-count substitution at the same
# id+file can therefore hide a swap; a known v1 limitation, reported in `note`
# rather than papered over.
fix_verify_diff() {
	_manifest_require_jq || return 1
	local baseline="${1:?baseline json file}" post="${2:?post json file}" changed="${3:-[]}"

	# A post-scan that is not well-formed is a failure, never an empty pass.
	if [ ! -f "$post" ] || ! jq -e '.findings' "$post" >/dev/null 2>&1; then
		jq -n '{status:"scanner-failed", verified:false,
		        note:"post-fix scan produced no parseable findings — cannot verify"}'
		return 3
	fi

	jq -n \
		--slurpfile base "$baseline" \
		--slurpfile new "$post" \
		--argjson changed "$changed" \
		--argjson clearing "$FIX_CLEARING_RULES_JSON" \
		"$FIX_STATIC_REPRODUCIBLE_JQ"'
		def key: "\(.id // "")@\(.file // "")";
		def is_clearing: (.id // "") as $i | ($clearing | index($i)) != null;
		def is_targeted: (.file // "") as $f | ($changed | index($f)) != null;
		def tally: [ .[] | select(is_static_reproducible) ] | group_by(key)
		           | map({key: (.[0] | key), id: .[0].id, file: .[0].file, count: length});

		(($base[0].findings // []) | tally) as $b
		| (($new[0].findings // []) | tally) as $n
		| ($b | map(.key)) as $bk
		| ($n | map(.key)) as $nk

		# Baseline static findings in files this run never touched. They MUST still
		# be there afterwards; if they all vanished, the scanner died rather than
		# the code improving.
		| [ ($base[0].findings // [])[]
			| select(is_static_reproducible)
			| select(is_targeted | not) ] as $untouched

		| if (($n | length) == 0) and (($untouched | length) > 0) then
			{ status: "scanner-failed", verified: false,
			  note: "post-fix scan returned zero findings while \($untouched | length) baseline finding(s) sit in files this run never touched — the scanner failed rather than the code improving" }
		  else
			[ $n[] | select((.key as $k | $bk | index($k)) == null) ] as $brand_new
			# Emit the POST-fix element, so `new[].count` is the grown count rather
			# than the stale baseline one. Iterating $n (not $b) also avoids
			# `EXPR as $c` yielding zero outputs when the key is absent post-fix.
			| [ $n[] | . as $x
				| ($b[] | select(.key == $x.key) | .count) as $was
				| select($x.count > $was)
				| $x + {was: $was, note: "count increased \($was) -> \($x.count)"} ] as $grown
			| ($brand_new + $grown) as $regressions
			| [ $b[] | select((.key as $k | $nk | index($k)) == null) ] as $resolved
			| [ $b[] | select((.key as $k | $nk | index($k)) != null) ] as $remain
			| [ $remain[] | select(is_targeted) | select(is_clearing) ] as $unresolved
			| [ $remain[] | select(is_targeted) | select(is_clearing | not)
			    | . + {note:"presence rule — the construct is still present (correctly, now guarded); this rule cannot clear. Not a failure."} ] as $still_flagged
			| [ $remain[] | select(is_targeted | not) ] as $untouched_still
			| { status: (if (($regressions | length) > 0) or (($unresolved | length) > 0) then "fail" else "pass" end),
			    verified: ((($regressions | length) == 0) and (($unresolved | length) == 0)),
			    resolved: $resolved,
			    unresolved: $unresolved,
			    stillFlagged: $still_flagged,
			    stillPresent: $untouched_still,
			    new: $regressions,
			    note: "verified = no regression AND every targeted clearing-rule finding gone. Presence-rule findings (7 of the 9 static rules) still match after a correct fix by construction and are reported as stillFlagged, not failure. Diff key is id+file by count; a same-count substitution at one id+file is not detectable in v1." }
		  end
	'
}

# -----------------------------------------------------------------------------
# Sub-command dispatcher: only runs when EXECUTED, not when sourced.
# Detect execution vs sourcing at top level (bash + zsh). Must NOT be wrapped in
# a function — zsh's ZSH_EVAL_CONTEXT loses the `:file` marker inside one.
# -----------------------------------------------------------------------------
_wp_fix_sourced=1
if [ -n "${BASH_VERSION:-}" ]; then
	[ "${BASH_SOURCE[0]}" = "$0" ] && _wp_fix_sourced=0
elif [ -n "${ZSH_VERSION:-}" ]; then
	case "${ZSH_EVAL_CONTEXT:-}" in *:file*) _wp_fix_sourced=1 ;; *) _wp_fix_sourced=0 ;; esac
fi

if [ "$_wp_fix_sourced" = "0" ]; then
	set -euo pipefail
	cmd="${1:-}"; shift || true
	case "$cmd" in
		load-findings) fix_load_findings "$@" ;;
		group-by-file) fix_group_by_file "$@" ;;
		rel-path)      fix_rel_path "$@"; echo ;;
		backup)        fix_backup "$@"; echo ;;
		restore)       fix_restore "$@"; echo ;;
		backup-init)   fix_backup_dir_init "$@"; echo ;;
		record)        fix_record "$@" ;;
		audit-age)     fix_audit_age_warn "$@" ;;
		rescan)        fix_static_rescan "$@" ;;
		baseline)      fix_baseline "$@" ;;
		verify)        fix_verify "$@" ;;
		verify-diff)   fix_verify_diff "$@" ;;
		*) echo "usage: wp-fix-lib.sh {load-findings|group-by-file|rel-path|backup|restore|backup-init|record|audit-age|rescan|baseline|verify|verify-diff} ..." >&2; exit 2 ;;
	esac
fi
