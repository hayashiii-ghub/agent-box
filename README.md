# agent-box

Apple Container で Claude Code を隔離コンテナに閉じ込めて「放牧」するための最小ツール。

## 使い方

```bash
box [プロジェクトのパス]            # 箱の中で claude を対話起動(省略時はカレント)
box [プロジェクトのパス] bash       # 箱の中の shell に入る
box [プロジェクトのパス] <コマンド>  # 箱の中で任意コマンドを実行
```

## 箱の中

- プロジェクトを `/work` にマウント(編集はホストに反映)
- 認証は `~/work/.sandbox-claude` のコピーをマウント(サブスクのまま・ホスト本体は触らない)
- `~/.gitconfig` を ro マウント(commit identity)、`--ssh` で SSH エージェント転送(push 用)
- `~/work/projects/hikizan` を `/opt/hikizan:ro` にマウントし `--plugin-dir` で読み込む(skill + hooks=floors)
- 上記以外の `~/work` は箱から不可視(隔離)

## 更新

- 焼き込み物(claude 本体など): `container build --no-cache -t agent-sandbox .`(`--no-cache` 必須)
- hikizan: ホストで `git pull` するだけ(マウントなので再ビルド不要)

## 要件

- Apple Silicon + macOS 26+(Apple Container)
- 箱は非 root / uid 501 で動かす(`--dangerously-skip-permissions` を使うため。root だと拒否される)
