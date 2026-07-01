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

初回のみ。設定は既定で `~/.config/agent-box/` 配下に置く(パスは環境変数で変更可、下記)。plugin は任意なので手順に含めない(使うなら「個人化」参照)。

1. **Apple Container を用意**(Apple Silicon + macOS 26+)。`container` コマンドが動くこと。
2. **このリポジトリを clone し、中に入って `box` を PATH に通す**:
   ```bash
   git clone <このリポジトリのURL> && cd agent-box
   ln -s "$PWD/box" /opt/homebrew/bin/box   # /opt/homebrew/bin は PATH 上のディレクトリなら何でも可
   ```
3. **Claude 認証を用意**(必須。ホスト本体でなくコピーを使う):
   ```bash
   mkdir -p ~/.config/agent-box/claude
   cp -R ~/.claude/. ~/.config/agent-box/claude/    # .credentials.json を含むコピー
   ```
4. **Codex 認証**(任意・codex を使うなら):
   ```bash
   mkdir -p ~/.config/agent-box/codex
   cp ~/.codex/auth.json ~/.config/agent-box/codex/  # auth.json のみ(host の重い config.toml は持ち込まない)
   ```
5. **gh トークン**(任意・箱から push / PR / gh API するなら):対象リポジトリに絞った PAT を作り保存:
   ```bash
   printf '%s' '<PAT>' > ~/.config/agent-box/gh-token && chmod 600 ~/.config/agent-box/gh-token
   ```
6. **イメージをビルド**:`box update`(初回ビルドも兼ねる。数分。uid はホストの `id -u` に自動追従)。

### パスを変えたい場合(環境変数で上書き)

`~/.config/agent-box` 以外に置きたいときは、`box` 実行時に次の env で上書きできる(未指定なら上記の既定):

- `AGENT_BOX_CLAUDE_CFG`(既定 `~/.config/agent-box/claude`)
- `AGENT_BOX_CODEX_CFG`(既定 `~/.config/agent-box/codex`)
- `AGENT_BOX_GH_TOKEN`(既定 `~/.config/agent-box/gh-token`)
- `AGENT_BOX_PLUGIN_DIR`(既定 `~/.config/agent-box/plugin` があれば自動で読み込む)

### 個人化 / plugin を使う(任意)

box は `~/.config/agent-box/plugin` を **plugin の既定の置き場**として自動で読み込む。ここに Claude plugin(skill + hooks)を置くか **symlink** すれば常時 ON(plugin 内に `skills/` があれば codex にも渡す)。無ければ素の Claude Code で起動する(`[box] plugin: なし` と表示)。

```bash
# 例: 手元の plugin を常時 ON にする(symlink なら編集が即反映される)
ln -s /path/to/your/claude-plugin ~/.config/agent-box/plugin
```

- 別の場所を指したいときは `export AGENT_BOX_PLUGIN_DIR=/path/...`(空文字 `AGENT_BOX_PLUGIN_DIR=` で強制 OFF)。
- plugin を持っていなければ、公開されている例として [hikizan](https://github.com/hayashiii-ghub/hikizan)(作者の skill + hooks)を clone して上の場所に symlink すると同じ体験になる。

**箱にコマンドを足したいとき**は、`Dockerfile` を編集せず build 時に渡せる:

```bash
AGENT_BOX_APT_EXTRA="ripgrep vim tree" box update   # 追加の apt パッケージを焼き込む
```

既定で `jq`(JSON整形)/ `less`(ページャ)は同梱済み。`gcc` / `make` / `python3` / `git` / `curl` 等はベースの `node` イメージに元から入っている。

### web/UI の視覚検証(sitesnap)を入れる(任意)

web/UI を触るなら [sitesnap](https://github.com/hayashiii-ghub/sitesnap)(Playwright + Chromium のスクショ / 視覚検証 CLI)を焼き込める。入れると「撮る → はみ出し / console エラー / a11y を判定 → 直す」の**視覚ループが箱の中で閉じる**(hikizan の skill は sitesnap があれば自動で視覚検証に使う)。Chromium 一式でイメージが数百MB太るので**既定は OFF**:

```bash
AGENT_BOX_WITH_SITESNAP=1 box update   # sitesnap + Chromium を焼き込む(web 対応版)
```

いつも web をやるなら、shell の profile に `export AGENT_BOX_WITH_SITESNAP=1` を書けば `box update` のたびに**常時 ON**(自分の箱だけ web 対応版・公開の既定は素のまま)。

> 箱の中で dev server を立てて撮るときは URL が localhost になる。sitesnap は安全のため private IP を既定でブロックするので `--allow-private` を付ける(dev server も sitesnap も同じ箱の中なので localhost で届く)。

## 箱の中

- プロジェクトを `/work` にマウント(編集はホストに反映)
- **Claude Code 認証**は `~/.config/agent-box/claude` のコピーをマウント(サブスクのまま・ホスト本体は触らない)
- **Codex 認証**は `~/.config/agent-box/codex`(`auth.json` のみ)のコピーをマウント(ホストの重い設定は持ち込まない)
- `~/.gitconfig` を ro マウント(commit identity)。**push は gh トークンを使った HTTPS** で通す(ホストの ssh 鍵は箱に渡さない → 箱が触れるのは GitHub 用の最小 PAT だけ)
- `AGENT_BOX_PLUGIN_DIR` を指定すると、その plugin を `/opt/plugin:ro` にマウントし `--plugin-dir` で読み込む(skill + hooks=floors)。**未指定なら素の `claude`**(このツールは特定 plugin に非依存)
- plugin に `skills/` があれば codex にも渡す(`/home/dev/.codex/skills:ro`。codex 側は **skill のみ**で hooks=floors は付かない)
- **GitHub CLI(`gh`)** を同梱。`~/.config/agent-box/gh-token` があれば `GH_TOKEN` として渡し、**同じトークンを `git push` の HTTPS 認証にも使う**(PR 作成・issue・GitHub API・push を1つの最小 PAT でまかなう)
- 上記以外のホストのディレクトリ(`/work` と認証マウント以外)は箱から不可視(隔離)

> `gh` を使うには、対象リポジトリに絞った PAT を作り `~/.config/agent-box/gh-token` に保存します(fine-grained なら **Contents** + **Pull requests** の Read/Write、classic なら **`repo`** だけ)。`chmod 600`・リポジトリ外なので push されません。`admin:public_key` など鍵を管理する権限は付けない(箱には最小権限だけ渡す方針)。

## 更新方針

再現性・起動速度・オフライン性のため、**起動毎の自動更新はしない**。更新は意図したタイミングで:

- 焼き込み物(claude / codex / gh 本体): `box update`(= `container build --no-cache`)
- plugin: ホスト側で更新するだけ(マウントなので再ビルド不要)

起動時、イメージが一定日数(既定 14 日)より古ければ「最新化は `box update`」というヒントを 1 行出すだけ(自動では更新しない)。ビルド末尾で claude/codex/gh の起動確認(smoke test)を行い、失敗したらビルドを止める(壊れたイメージにタグを付け替えないので、直前の動くイメージが残る)。

## 仕組みのポイント

- **非 root** で動かす(`--dangerously-skip-permissions` は root だと拒否されるため)。コンテナ内 uid はホストの `id -u` に自動追従させ、マウントしたファイルを読み書きできるようにする
- 箱内 git を有効化するため、イメージに `safe.directory` を焼き込み済み(マウント越しの dubious ownership を回避)。push はホストの ssh 鍵ではなく **gh トークンの HTTPS** で通す(箱に渡す鍵の範囲を GitHub の push 用途だけに絞るため。`box` 側で `git@github.com:` → token 付き HTTPS に `insteadOf` 書き換え)
- gh の apt 署名鍵は sha256 で pin(HTTPS 取得した鍵をそのまま信頼せず素性検証してから apt に渡す)
- 認証トークンは箱に**コピー**を渡す方式で、ホスト本体の認証情報には触れさせない

## セキュリティ / 隔離の実力

放牧(`--dangerously-skip-permissions` で人間の確認なしに走らせる)前提のツールなので、**何が守れて何が守れないか**を明示しておく。

**守れる**: Apple Container の VM 隔離により、ホスト(母艦 Mac)のファイルシステム・カーネルへの直接アクセスは防ぐ(Docker より強い)。`/work` と認証マウント以外のホストのディレクトリは箱から不可視。ホストの認証情報「本体」は触らせない(箱に渡すのはコピー)。

**守れない(= 設計上あえて受容しているリスク)**:

- **箱に渡した認証情報は持ち出され得る。** 箱の中には Claude 認証コピー / codex `auth.json` / `GH_TOKEN` が同居し、外向き通信は自由。放牧エージェントが web や issue の悪意ある指示(prompt injection)に乗ると、これらを外部へ送信され得る。VM 隔離は **ネットへの持ち出しは止めない**。→ 箱に渡す認証は「漏れうる前提」で、**gh トークンは対象リポジトリ限定・最小権限・使い捨て可能**なものにする。
- **floors(plugin の hooks)は認可の壁ではない。** `git push` / `rm -*` 等のコマンド文字列を事前停止する「Claude の事故抑制」であって、`GH_TOKEN` がある以上 `gh api` 直叩き等で迂回できる。codex には floors 自体が付かない。**実効的な認可境界は PAT の権限設定だけ**。
- **`/work` 経由の“時間差”実行。** 箱は `/work`(= 対象リポジトリ)を書き換えられる。`.git/hooks/*` や `package.json` の `postinstall`、`Makefile` 等を仕込まれると、後で **ホスト側で** `git` / `npm` / `make` した瞬間にホストで実行される。→ 箱で作業したリポジトリの差分(特に hooks / postinstall / lockfile)は **信頼せず目視** する。
- **認証マウントは永続。** `~/.config/agent-box/claude` 等はホストの永続ディレクトリなので、箱内エージェントが悪性の `settings.json` / hooks を書き込むと次回起動に持ち越す。→ 気になるなら **定期的に pristine(ホスト `~/.claude` からの再コピー)で作り直す**。
- **内部ネットワーク到達は環境依存。** 箱から LAN 内ホストや metadata endpoint(`169.254.169.254` 等)に届くかは Apple Container のネットワーク設定次第。心配なら一度 `box . bash` で `curl -m2 http://169.254.169.254/` 等の到達可否を実測する。

**一言まとめ**: 「**ホストは守れる。箱に渡した認証情報と、いじらせたリポジトリは守れない**」。個人利用・最小権限 PAT・使い捨て前提なら受容可能なトレードオフ。さらに強く絞るなら、箱の外向き通信を許可リスト(github / anthropic / openai / npm のみ)化するのが次の一手(現状は未実装 = 受容)。

## 要件

- Apple Silicon + macOS 26+([Apple Container](https://github.com/apple/container))

## License

[MIT](./LICENSE)
