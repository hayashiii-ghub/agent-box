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

## セットアップ

初回のみ。以下は既定の `~/work` レイアウト前提(パスは環境変数で変更可、下記)。hikizan は任意なので手順に含めない(持っていれば自動で有効化される)。

1. **Apple Container を用意**(Apple Silicon + macOS 26+)。`container` コマンドが動くこと。
2. **このリポジトリを clone し、中に入って `box` を PATH に通す**:
   ```bash
   git clone <このリポジトリのURL> && cd agent-box
   ln -s "$PWD/box" /opt/homebrew/bin/box   # /opt/homebrew/bin は PATH 上のディレクトリなら何でも可
   ```
3. **Claude 認証を用意**(必須。ホスト本体でなくコピーを使う):
   ```bash
   mkdir -p ~/work/.sandbox-claude
   cp -R ~/.claude/. ~/work/.sandbox-claude/    # .credentials.json を含むコピー
   ```
4. **Codex 認証**(任意・codex を使うなら):
   ```bash
   mkdir -p ~/work/.sandbox-codex
   cp ~/.codex/auth.json ~/work/.sandbox-codex/  # auth.json のみ(host の重い config.toml は持ち込まない)
   ```
5. **gh トークン**(任意・箱から push / PR / gh API するなら):対象リポジトリに絞った PAT を作り保存:
   ```bash
   printf '%s' '<PAT>' > ~/work/.sandbox-gh-token && chmod 600 ~/work/.sandbox-gh-token
   ```
6. **イメージをビルド**:`box update`(初回ビルドも兼ねる。数分。uid はホストの `id -u` に自動追従)。

### パスを変えたい場合(環境変数で上書き)

`~/work` 以外に置きたいときは、`box` 実行時に次の env で上書きできる(未指定なら上記の既定):

- `AGENT_BOX_CLAUDE_CFG`(既定 `~/work/.sandbox-claude`)
- `AGENT_BOX_CODEX_CFG`(既定 `~/work/.sandbox-codex`)
- `AGENT_BOX_HIKIZAN`(既定 `~/work/projects/hikizan`)
- `AGENT_BOX_GH_TOKEN`(既定 `~/work/.sandbox-gh-token`)

## 箱の中

- プロジェクトを `/work` にマウント(編集はホストに反映)
- **Claude Code 認証**は `~/work/.sandbox-claude` のコピーをマウント(サブスクのまま・ホスト本体は触らない)
- **Codex 認証**は `~/work/.sandbox-codex`(`auth.json` のみ)のコピーをマウント(ホストの重い設定は持ち込まない)
- `~/.gitconfig` を ro マウント(commit identity)。**push は gh トークンを使った HTTPS** で通す(ホストの ssh 鍵は箱に渡さない → 箱が触れるのは GitHub 用の最小 PAT だけ)
- `~/work/projects/hikizan` を `/opt/hikizan:ro` にマウントし `--plugin-dir` で読み込む(skill + hooks=floors)。**hikizan は任意** — 無ければ自動で素の `claude` として起動する(このツールは hikizan 非依存)
- hikizan の `skills/` を codex にも渡す(`/home/dev/.codex/skills:ro`。codex 側は **skill のみ**で hooks=floors は付かない)
- **GitHub CLI(`gh`)** を同梱。`~/work/.sandbox-gh-token` があれば `GH_TOKEN` として渡し、**同じトークンを `git push` の HTTPS 認証にも使う**(PR 作成・issue・GitHub API・push を1つの最小 PAT でまかなう)
- 上記以外の `~/work` は箱から不可視(隔離)

> `gh` を使うには、対象リポジトリに絞った PAT を作り `~/work/.sandbox-gh-token` に保存します(fine-grained なら **Contents** + **Pull requests** の Read/Write、classic なら **`repo`** だけ)。`chmod 600`・リポジトリ外なので push されません。`admin:public_key` など鍵を管理する権限は付けない(箱には最小権限だけ渡す方針)。

## 更新方針

再現性・起動速度・オフライン性のため、**起動毎の自動更新はしない**。更新は意図したタイミングで:

- 焼き込み物(claude / codex / gh 本体): `box update`(= `container build --no-cache`)
- hikizan: ホストで `git pull` するだけ(マウントなので再ビルド不要)

起動時、イメージが一定日数(既定 14 日)より古ければ「最新化は `box update`」というヒントを 1 行出すだけ(自動では更新しない)。

## 仕組みのポイント

- **非 root / uid 501** で動かす(`--dangerously-skip-permissions` は root だと拒否されるため。uid をホストに合わせるとマウントしたファイルを読み書きできる)
- 箱内 git を有効化するため、イメージに `safe.directory` を焼き込み済み(マウント越しの dubious ownership を回避)。push はホストの ssh 鍵ではなく **gh トークンの HTTPS** で通す(箱に渡す鍵の範囲を GitHub の push 用途だけに絞るため。`box` 側で `git@github.com:` → token 付き HTTPS に `insteadOf` 書き換え)
- 認証トークンは箱に**コピー**を渡す方式で、ホスト本体の認証情報には触れさせない

## セキュリティ / 隔離の実力

放牧(`--dangerously-skip-permissions` で人間の確認なしに走らせる)前提のツールなので、**何が守れて何が守れないか**を明示しておく。

**守れる**: Apple Container の VM 隔離により、ホスト(母艦 Mac)のファイルシステム・カーネルへの直接アクセスは防ぐ(Docker より強い)。`/work` 以外の `~/work` を含むホストの他ディレクトリは箱から不可視。ホストの認証情報「本体」は触らせない(箱に渡すのはコピー)。

**守れない(= 設計上あえて受容しているリスク)**:

- **箱に渡した認証情報は持ち出され得る。** 箱の中には Claude 認証コピー / codex `auth.json` / `GH_TOKEN` が同居し、外向き通信は自由。放牧エージェントが web や issue の悪意ある指示(prompt injection)に乗ると、これらを外部へ送信され得る。VM 隔離は **ネットへの持ち出しは止めない**。→ 箱に渡す認証は「漏れうる前提」で、**gh トークンは対象リポジトリ限定・最小権限・使い捨て可能**なものにする。
- **floors(hikizan hooks)は認可の壁ではない。** `git push` / `rm -*` 等のコマンド文字列を事前停止する「Claude の事故抑制」であって、`GH_TOKEN` がある以上 `gh api` 直叩き等で迂回できる。codex には floors 自体が付かない。**実効的な認可境界は PAT の権限設定だけ**。
- **`/work` 経由の“時間差”実行。** 箱は `/work`(= 対象リポジトリ)を書き換えられる。`.git/hooks/*` や `package.json` の `postinstall`、`Makefile` 等を仕込まれると、後で **ホスト側で** `git` / `npm` / `make` した瞬間にホストで実行される。→ 箱で作業したリポジトリの差分(特に hooks / postinstall / lockfile)は **信頼せず目視** する。
- **認証マウントは永続。** `~/work/.sandbox-claude` 等はホストの永続ディレクトリなので、箱内エージェントが悪性の `settings.json` / hooks を書き込むと次回起動に持ち越す。→ 気になるなら **定期的に pristine(ホスト `~/.claude` からの再コピー)で作り直す**。
- **内部ネットワーク到達は環境依存。** 箱から LAN 内ホストや metadata endpoint(`169.254.169.254` 等)に届くかは Apple Container のネットワーク設定次第。心配なら一度 `box . bash` で `curl -m2 http://169.254.169.254/` 等の到達可否を実測する。

**一言まとめ**: 「**ホストは守れる。箱に渡した認証情報と、いじらせたリポジトリは守れない**」。個人利用・最小権限 PAT・使い捨て前提なら受容可能なトレードオフ。さらに強く絞るなら、箱の外向き通信を許可リスト(github / anthropic / openai / npm のみ)化するのが次の一手(現状は未実装 = 受容)。

## 要件

- Apple Silicon + macOS 26+([Apple Container](https://github.com/apple/container))

## License

[MIT](./LICENSE)
