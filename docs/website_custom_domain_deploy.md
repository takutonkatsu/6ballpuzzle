# Website GitHub Pages Deploy

公式サイト、利用規約、プライバシーポリシーを `takutonkatsu.com/Hexagon/` で公開する手順です。
`takutonkatsu.com/` から `/Hexagon/` への自動転送は行いません。

## DNS

`takutonkatsu.com` は GitHub Pages のユーザーサイト `takutonkatsu.github.io` に向けます。
`takutonkatsu.com/Retina/` と同じ仕組みで、`Hexagon` リポジトリをプロジェクトサイトとして公開します。

GitHub Pages の Custom domain は `takutonkatsu.github.io` 側で管理し、`Hexagon` リポジトリ側には設定しません。

## GitHub Pages

GitHub の `takutonkatsu/Hexagon` リポジトリで以下を設定します。

1. Settings > Pages を開きます。
2. Source を `Deploy from a branch` にします。
3. Branch を `main`、Folder を `/root` にします。
4. Custom domain は空欄のままにします。
5. Save します。

## Deploy

ローカルの `website/` 配下だけを `takutonkatsu/Hexagon` リポジトリへ配置します。

```bash
cd /Users/takuto/development/6ballpuzzle

tmp_dir="$(mktemp -d)"
rsync -av --delete \
  --exclude '.DS_Store' \
  website/ \
  "$tmp_dir/"
touch "$tmp_dir/.nojekyll"

cd "$tmp_dir"
git init
git branch -M main
git add .
git commit -m "Deploy Hexagon official site"
git remote add origin git@github.com:takutonkatsu/Hexagon.git
git push -u origin main
```

2回目以降は既存の `Hexagon` リポジトリをcloneまたはpullして、同じ内容を同期してpushします。

## Verify

```bash
curl -I https://takutonkatsu.github.io/Hexagon/
curl -I https://takutonkatsu.com/Hexagon/
curl -I https://takutonkatsu.com/Hexagon/privacy.html
curl -I https://takutonkatsu.com/Hexagon/terms.html
curl -I https://takutonkatsu.com/
```

`https://takutonkatsu.com/` は `/Hexagon/` にリダイレクトしないことを確認します。

## App URL

アプリ内のプライバシーポリシーURLは `https://takutonkatsu.com/Hexagon/privacy.html` にします。
