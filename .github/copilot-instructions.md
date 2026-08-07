
## GitHub Raw Access URL の生成ルール
raw.githubusercontent.com のURLは必ず以下の形式に従うこと。
  https://raw.githubusercontent.com/<owner>/<repo>/<branch-or-sha>/<path>
- `github.com/.../blob/...` 形式や `github.com/.../raw/...` 形式を使用しない
- ブランチ名は `refs/heads/` を含めない
- pathの先頭にスラッシュを重複させない
このルールは coding agent による自動生成・再生成時にも常に適用すること。
