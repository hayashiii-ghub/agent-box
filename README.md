# agent-box

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

[Apple Container](https://github.com/apple/container) で AI エージェント CLI(Claude Code / Codex)を隔離コンテナに閉じ込めて「放牧」するための最小ツール。各コンテナが専用の軽量 VM で動くので、ホストから強く隔離した状態でエージェントを自由に走らせられる。

## 使い方

```bash
box                              # カレントのプロジェクトで claude を対話起動
box <プロジェクトのパス>           # 指定したプロジェクトで claude を対話起動
box <プロジェクトのパス> bash      # 箱の中の shell に入る
box <プロジェクトのパス> codex     # 箱の中で codex を起動
box <プロジェクトのパス> <コマンド> # 箱の中で任意コマンドを実行
box update                       # イメージを最新化(claude/codex を再ビルド。手動更新)
```

> コマンド(`bash` / `codex` など)を付けるときは**パスを省略できません**。今いるフォルダで使うなら `box . bash` のように `.`(=カレント)を明示します(`box` 単体のときだけカレントが既定)。

## 箱の中

- プロジェクトを `/work` にマウント(編集はホストに反映)
- **Claude Code 認証**は `~/work/.sandbox-claude` のコピーをマウント(サブスクのまま・ホスト本体は触らない)
- **Codex 認証**は `~/work/.sandbox-codex`(`auth.json` のみ)のコピーをマウント(ホストの重い設定は持ち込まない)
- `~/.gitconfig` を ro マウント(commit identity)、`--ssh` で SSH エージェント転送(push 用)
- `~/work/projects/hikizan` を `/opt/hikizan:ro` にマウントし `--plugin-dir` で読み込む(skill + hooks=floors)
- 上記以外の `~/work` は箱から不可視(隔離)

## 更新方針

再現性・起動速度・オフライン性のため、**起動毎の自動更新はしない**。更新は意図したタイミングで:

- 焼き込み物(claude / codex 本体): `box update`(= `container build --no-cache`)
- hikizan: ホストで `git pull` するだけ(マウントなので再ビルド不要)

起動時、イメージが一定日数(既定 14 日)より古ければ「最新化は `box update`」というヒントを 1 行出すだけ(自動では更新しない)。

## 仕組みのポイント

- **非 root / uid 501** で動かす(`--dangerously-skip-permissions` は root だと拒否されるため。uid をホストに合わせるとマウントしたファイルを読み書きできる)
- 箱内 git を有効化するため、イメージに `safe.directory` と GitHub の host key を焼き込み済み(マウント越しの dubious ownership と `Host key verification failed` を回避)
- 認証トークンは箱に**コピー**を渡す方式で、ホスト本体の認証情報には触れさせない

## 要件

- Apple Silicon + macOS 26+([Apple Container](https://github.com/apple/container))

## License

[MIT](./LICENSE)
