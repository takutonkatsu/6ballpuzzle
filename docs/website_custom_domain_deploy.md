# Website Custom Domain Deploy

公式サイト、利用規約、プライバシーポリシーを `takutonkatsu.com/hexagon/` で公開する手順です。

## DNS

お名前.comで以下を設定します。

| TYPE | ホスト名 | VALUE |
| --- | --- | --- |
| A | 空欄 または `@` | `178.128.103.157` |
| A | `www` | `178.128.103.157` |

`realtime.hexagon.takutonkatsu.com` はWebSocket専用なので、そのまま残します。

## Dropletでの配置

ローカルの `website/` 配下だけを `/var/www/hexagon` に配置します。

```bash
sudo mkdir -p /var/www/hexagon
sudo rsync -av --delete \
  --exclude '.DS_Store' \
  /path/to/6ballpuzzle/website/ \
  /var/www/hexagon/
sudo chown -R www-data:www-data /var/www/hexagon
```

Droplet上にリポジトリを置いていない場合は、ローカルMacから次のように送ります。

```bash
rsync -av --delete \
  --exclude '.DS_Store' \
  website/ \
  root@178.128.103.157:/var/www/hexagon/
```

## Nginx

`docs/nginx_hexagon_site.conf` をDropletの `/etc/nginx/sites-available/hexagon-site` に配置し、有効化します。

```bash
sudo cp docs/nginx_hexagon_site.conf /etc/nginx/sites-available/hexagon-site
sudo ln -sf /etc/nginx/sites-available/hexagon-site /etc/nginx/sites-enabled/hexagon-site
sudo nginx -t
sudo systemctl reload nginx
```

HTTPS証明書を発行します。

```bash
sudo certbot --nginx -d takutonkatsu.com -d www.takutonkatsu.com
```

確認:

```bash
curl -I https://takutonkatsu.com/
curl -I https://takutonkatsu.com/hexagon/
curl -I https://takutonkatsu.com/hexagon/privacy.html
curl -I https://takutonkatsu.com/hexagon/terms.html
curl -I https://takutonkatsu.com/privacy.html
```

## アプリ側URL

アプリ内のプライバシーポリシーURLは `https://takutonkatsu.com/hexagon/privacy.html` にします。

旧URLは301リダイレクトで新URLへ流します。
