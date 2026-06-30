# Brainstorm — `/wp-pro-max:init` project scaffolder

- **Date:** 2026-06-26
- **Status:** design approved, ready for `/ck:plan`
- **Modes:** none (no `--html` / `--wiki`)

## Problem statement

Plugin chạy trên một *target WordPress project* riêng (CWD nơi gọi `build`), nhưng
**chưa có quy ước thư mục** cho target đó. `build` chỉ nhận 1 arg path
(`html-dir | url | brief.md`); user tự quyết để input ở đâu, output đi đâu. Thiếu
một bước khởi tạo chuẩn → mỗi project một kiểu, dễ sai input, khó resume.

Mục tiêu: thêm command `/wp-pro-max:init` tạo cấu trúc thư mục chuẩn cho target
project + **ghi sẵn `wp-build.json`** nối các folder vào pipeline, để `build`
chạy được ngay. Phục vụ input/output của 16 stage (không phải "8+1").

## Requirements (chốt qua Discovery)

- **Expected output:** command `commands/init.md`; chạy xong có cây thư mục +
  `wp/wp-build.json` đã wire `source.*` + `brief.md`, `.gitignore`, `README.md`.
- **Acceptance:** sau `init` rồi `cd wp && /wp-pro-max:build` (hoặc build từ root
  cha nhờ auto-descend) chạy được, đọc đúng input từ `../source`, `../assets`,
  `../requirements/brief.md`.
- **Scope boundary:** chỉ folders + manifest + 3 template file; KHÔNG Docker,
  KHÔNG skill, KHÔNG đổi schema.
- **Constraints:** command-only (đúng convention: init không phải pipeline stage);
  tái dùng `wpbuild_init`; zsh-safe; namespaced theme slug.
- **Touchpoints:** `commands/init.md` (mới), `commands/build.md` (auto-descend),
  `scripts/manifest-lib.sh` (tái dùng), docs.

## Approaches đã cân nhắc

| Quyết định | Chọn | Loại bỏ vì |
|---|---|---|
| Scope | Folders + manifest | "Chỉ folders" → folder rời pipeline thành rác; "+wp-env" → trùng việc stage env, nặng |
| Layout | Parent-wrapper (inputs ở root, WP trong `wp/`) | Single-root gộp được nhưng user muốn tách input/WP rõ ràng |
| Component | Command only | Skill thừa — init không nằm trong 16 canonical stage ids |
| Build tìm manifest | Dạy build auto-descend vào `./wp/` | "Chỉ in cd" → foot-gun; "--wp-dir" → phức tạp chưa cần |
| Templates | brief.md, .gitignore, README.md | design/token starter: chưa cần (YAGNI) |

## Giải pháp cuối

### Cây thư mục
```
<project-name>/
  requirements/  brief.md        # template → analyze/model
  source/        .gitkeep        # static HTML/CSS/JS (source.htmlPaths)
  assets/        .gitkeep        # ảnh/font nguồn (source.assetDirs)
  design/        .gitkeep        # design ref (convention, chưa wire manifest)
  mockups/       .gitkeep        # screenshot cho qa visual-diff (convention)
  wp/                            # WP PROJECT ROOT (CWD build + wp-env)
    wp-build.json                # init ghi sẵn
  .gitignore
  README.md
```
`wp-content/themes/<slug>/` + `.wp-env.json` do stage scaffold/env sinh trong `wp/`.

### `init` procedure
1. Derive `project.name` (arg | tên CWD), `themeSlug` (kebab, namespaced),
   `strategy` (mặc định `classic-acf` | `--strategy`).
2. Tạo cây thư mục + `.gitkeep`.
3. Ghi `wp/wp-build.json` qua `wpbuild_init` (tái dùng, không viết lại).
4. Set `source.*` path **tương đối với `wp/`**: `source.type`,
   `htmlPaths=["../source"]`, `assetDirs=["../assets"]`,
   `briefPath="../requirements/brief.md"`.
5. Sinh `brief.md`, `.gitignore`, `README.md`.
6. In next-step: `cd wp && /wp-pro-max:build`.

### Build auto-descend
`commands/build.md` bước "Init/resume": nếu CWD không có `wp-build.json` nhưng có
`./wp/wp-build.json` → cd vào `wp/` rồi tiếp tục. User gõ `build` từ root cha vẫn chạy.

## Touchpoints / files

| File | Action |
|---|---|
| `commands/init.md` | CREATE — command scaffold + `wpbuild_init` + set source |
| `commands/build.md` | EDIT — ~5 dòng auto-descend `./wp/` |
| `scripts/manifest-lib.sh` | reuse `wpbuild_init`/`wpbuild_set` (thêm helper set-source nếu gọn hơn) |
| `README.md`, `docs/codebase-summary.md`, `docs/system-architecture.md` | EDIT — Commands list +init, mô tả layout convention |

## Ngoài scope (cố ý)
- Không đổi `schemas/wp-build.schema.json` (design/mockups là folder tham chiếu,
  chưa stage nào đọc field `designDir`/`mockupsDir`).
- Không Docker/wp-env trong init. Không skill.

## Rủi ro
- Path tương đối `../source` phụ thuộc build chạy từ `wp/` → đã xử lý bằng
  auto-descend; cần test cả 2 cách gọi (từ root cha và từ trong `wp/`).
- `init` chạy lại trên project đã có manifest → phải idempotent: `wpbuild_init`
  đã no-op khi file tồn tại; folder dùng `mkdir -p`; template không ghi đè nếu đã có.

## Validation
- `bash -n commands` không áp dụng (md); kiểm `claude plugin validate .`.
- Behavioral: chạy init vào thư mục tạm → kiểm tra cây thư mục + nội dung
  `wp/wp-build.json` (jq) + build auto-descend (mock `WP_CLI_RUN="echo"`).

## Open questions
- `wp/` có nên đổi tên theo `<slug>` mặc định không? (hiện cố định `wp/`, có thể
  thêm `--wp-dir` sau nếu cần — đã loại khỏi scope vòng này.)
- `design/`/`mockups/` khi nào nâng thành field manifest first-class? (chờ stage
  thực sự đọc chúng — qa visual-diff hiện đối chiếu `source/`, chưa cần.)
