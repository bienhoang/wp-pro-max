# Brainstorm — WooCommerce Catalog Build Extension (SP1)

**Date:** 2026-06-26 · **Status:** approved (design) · **Skill:** /brainstorm
**Modes:** none (no --html/--wiki)
**Next:** /ck:plan (default)

## Problem statement

`wp-pro-max` (Claude Code plugin, HTML→WordPress pipeline) chưa dựng được cửa
hàng WooCommerce. Schema đã có enum `ecommerce` nhưng không stage nào dùng;
`plugin-selection` thiếu dòng Woo; `plugin-data-seeding` không seed product. Cần
khả năng "quản lý + phát triển WooCommerce" — đã decompose; vòng này chỉ làm
**SP1: build cửa hàng catalog-only** qua pipeline hiện có.

## Requirements (chốt qua hỏi-đáp)

- **Scope tổng:** cả build + quản lý → decompose 3 sub-project; vòng này = SP1.
- **Depth:** catalog-only (chưa cart/checkout/payment).
- **Nguồn phát hiện:** cả HTML signals + brief/flag tường minh.
- **Tích hợp strategy:** layer cross-cutting (KHÔNG strategy thứ 4).
- **Tổ chức code:** mở rộng skill hiện có (KHÔNG skill/stage mới).

### Expected output
Mở rộng plugin để pipeline sinh ra cửa hàng WooCommerce catalog: schema thêm
`commerce`; analyze phát hiện; model→catalog; plugins chọn Woo; convert+scaffold
override template Woo theo strategy; seed products/categories/ảnh idempotent; QA
trang shop/product; 2 reference doc Woo; docs cập nhật.

### Acceptance criteria
Input HTML có product card (hoặc brief bật commerce) → wp-env WordPress có Woo
active, categories+attributes+products+ảnh seeded idempotent, `/shop/` + single
product render 200 có style theme, re-run không trùng, `claude plugin validate .`
pass, scripts `bash -n` + zsh-safe.

### Out of scope (SP1)
Cart/checkout/payment/shipping/tax (→SP3), cổng VN VietQR/SePay (→SP3), quản lý
store live + đơn hàng (→SP2), coupon, multi-currency, variable product phức tạp.

## Decomposition

| Sub-project | Nội dung | Trạng thái |
|---|---|---|
| **SP1** | Commerce build extension — catalog-only (vòng này) | đang plan |
| **SP2** | Store management & development surface (kết nối store live, quản lý đơn/sp, dev extension) | brainstorm riêng sau |
| **SP3** | Commerce depth upgrade — full checkout + cổng VN + shipping (xây trên SP1) | backlog |

## Evaluated approaches

### Tích hợp strategy: cross-cutting vs strategy thứ 4 → **cross-cutting** ✅
- Woo tự đăng ký `product` CPT + taxonomies, theme chỉ override (`woocommerce/`,
  hook, `add_theme_support`). Chạy dưới cả 3 strategy.
- Strategy thứ 4 sai: store thật vẫn cần strategy cho trang non-shop; mất tính
  kết hợp (Woo+Elementor, Woo+FSE); enum strategy là mutually-exclusive.
- → Thêm khối `commerce` độc lập vào manifest; logic Woo gắn vào stage sở hữu.

### Tổ chức code: extend vs skill mới → **extend (cross-cutting)** ✅
- Mở rộng skill hiện có + 2 reference doc tập trung. YAGNI; khớp "Woo là layer".
- Skill `wp-commerce` riêng: tập trung hơn nhưng thêm stage thừa, lệch quyết định.

## Recommended solution

### Manifest — thêm `commerce` (schemas/wp-build.schema.json)
```jsonc
"commerce": {
  "enabled": true, "platform": "woocommerce", "depth": "catalog",
  "detectedFrom": ["html","brief"],
  "catalog": {
    "categories": [{ "slug","name","parent","image" }],
    "attributes": [{ "slug","name","terms":[] }],
    "products": [{ "slug","name","type":"simple|variable","sku",
      "regularPrice","salePrice","currency","shortDescription","description",
      "categories":[],"images":[],"gallery":[],"attributes":[],"stockStatus":"instock" }]
  },
  "settings": { "currency":"VND","currencyPos","weightUnit","baseLocation" },
  "seededProductSlugs": []
}
```

### Thay đổi theo stage (touchpoints)

| Stage / file | Thêm |
|---|---|
| `skills/html-analysis/SKILL.md` | Heuristics commerce: product grid lặp, price token (`$ ₫ VND`), add-to-cart/buy, breadcrumb shop → set `commerce.enabled` + gợi ý catalog. |
| `skills/content-modeling/SKILL.md` + `references/woocommerce-model.md` (mới) | Map HTML/brief → `commerce.catalog` (không đăng ký product CPT — Woo lo). |
| `skills/plugin-selection/SKILL.md` | Dòng bảng: e-commerce → `woocommerce` (`category: ecommerce`, `required` khi enabled); pin `.wp-env.json`. |
| `skills/theme-conversion` references (classic-acf/block-fse/page-builder) | Mục Woo override mỗi backend (classic: `woocommerce/` + `add_theme_support`; FSE: Woo block templates; builder: Woo widgets note). |
| `skills/wp-scaffold/SKILL.md` | `add_theme_support('woocommerce')` + `woocommerce/` template parts tối thiểu style theo design tokens. |
| `skills/plugin-data-seeding/SKILL.md` + `references/woocommerce-seeding.md` (mới) | Nhánh khi `woocommerce ∈ plugins[]`: seed categories→attributes→products qua `wp wc` (hoặc `wp post create` + meta), `wp media import` ảnh, idempotent theo slug. |
| `scripts/seed-helpers.sh` | `ensure_wc_product`, `ensure_wc_term` (check-before-create, zsh-safe). |
| `skills/wp-qa/SKILL.md` | Smoke `/shop/` + 1 single product render 200 có giá+ảnh; visual-diff nếu HTML gốc có shop. |
| `commands/build.md` | Ghi chú commerce cross-cutting (no new stage); gate sau `plugins`. |
| `agents/wp-data-engineer.md`, `wp-theme-developer.md` | Acceptance: product seed idempotent; Woo template render đúng. |
| `docs/system-architecture.md`, `codebase-summary.md`, `project-roadmap.md` | Ghi trục commerce + SP2/SP3 backlog. |

### Catalog seed (catalog-only)
- **Có:** simple products, categories phân cấp, attributes+terms, ảnh featured+
  gallery, regular/sale price, SKU, mô tả ngắn/dài, stock flag `instock`.
- **Best-effort:** variable products (chỉ khi HTML lộ rõ; phức tạp → note, bỏ qua).
- **Settings:** currency (VND mặc định), currency position, base location, weight unit.

### Detection (cả hai nguồn)
- HTML: heuristics trong `html-analysis` → tự bật.
- Brief/flag: brief nói "shop/bán hàng" hoặc `--commerce` ép bật; brief override HTML.

### Idempotency & an toàn
- Seed theo slug, check-before-create, ghi `commerce.seededProductSlugs`; re-run không trùng.
- Ảnh dedupe theo filename trước `wp media import`.
- Raw SQL: dry-run/SELECT trước (theo contract); ưu tiên `wp wc` CLI.

## Risks

1. `wp wc` CLI cần Woo active trước seed → thứ tự env→install→activate→seed (orchestrator đảm bảo plugins trước seed).
2. FSE+Woo block templates phức tạp → SP1 chỉ đảm bảo render + style cơ bản, không pixel-perfect.
3. Detection false positive (giá ở landing page) → gate user xác nhận `commerce.enabled` sau analyze.
4. Live e2e chưa verify (không Docker trong môi trường build) — rủi ro sẵn có, để v0.2.

## Success metrics / validation
- `claude plugin validate .` pass; scripts `bash -n` + zsh-safe; node `--check` clean.
- Mock-WP-CLI test cho `ensure_wc_*` helper (như `seed-helpers.sh` hiện có).
- Live e2e (khi có Docker): seed → `/shop/` + single product render đúng, re-run sạch.

## Next steps / dependencies
- /ck:plan (default) phân phase: schema → detection → modeling → selection → convert/scaffold → seeding helpers+ref → qa → docs.
- Phụ thuộc: WooCommerce wporg slug `woocommerce`; `wp wc` CLI (đi kèm Woo); ảnh nguồn từ optimization stage.
- SP2/SP3 brainstorm riêng về sau.

## Open questions
- `wp wc` CLI có sẵn khi Woo cài qua wp-env không, hay cần `wp plugin activate` rồi mới có namespace `wc`? (verify ở plan/e2e).
- Variable product: có cần ở SP1 không, hay đẩy hẳn sang SP3? (mặc định: best-effort, không bắt buộc).
