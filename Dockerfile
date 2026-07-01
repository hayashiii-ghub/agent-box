# Apple Container 用「エージェント放牧」サンドボックス
# 箱の中で Claude Code を隔離して走らせるための最小イメージ。
# ベースは node:22 タグ(freshness 優先: box update のたびに最新の 22.x とパッチを拾う)。
# 特定バージョンに固定したい重要更新時は node:22@sha256:... の digest pin にする
# (再現性 ⇔ freshness のトレードオフ。通常は freshness を優先)。
FROM docker.io/library/node:22

# ベースイメージ(Debian)の OS パッケージをセキュリティ修正込みで最新化する。
# これが無いと node:22 公開時点の古い OS パッケージのまま固まり、公開後に出た
# 既知CVEの修正(openssl/glibc/git/openssh 等)が取り込まれない。box update
# (--no-cache 再ビルド)のたびに最新パッチを拾う。最後に apt のインデックス
# キャッシュを消してイメージを小さく保つ。
RUN apt-get update && apt-get upgrade -y \
 && rm -rf /var/lib/apt/lists/*

# GitHub CLI(gh)を公式 apt リポジトリから入れる。箱の中のエージェントが
# PR 作成・issue・GitHub API を自走できるようにするため。git push は --ssh の
# エージェント転送で通るが、gh は別系統(トークン認証)なので gh 本体が要る。
# 公式リポジトリ経由なので box update(--no-cache 再ビルド)のたびに最新版を拾う。
RUN mkdir -p -m 755 /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y gh \
 && rm -rf /var/lib/apt/lists/*

# エージェントCLIを事前インストール(毎回 npm install しないで済む)
# 更新はこのイメージを焼き直す(container build)ことで行う。
# claude-code 2.1.x はネイティブbinaryを arch別 optionalDependency で配るが、build 時に
# optional が取りこぼされ "native binary not installed" になることがある。対策として
# linux-arm64 native を明示インストールし、install.cjs を再実行して binary を紐付ける
# (箱は Apple Silicon=arm64 前提)。
RUN npm install -g @anthropic-ai/claude-code @anthropic-ai/claude-code-linux-arm64 @openai/codex \
 && node /usr/local/lib/node_modules/@anthropic-ai/claude-code/install.cjs

# 箱の中では自動アップデートしない(焼き込み式・再現性のため。書込不可で失敗する警告も消える)
ENV DISABLE_AUTOUPDATER=1

# 非rootユーザー。uid をホスト(501)に合わせる理由:
#  - マウントしたファイル(ホスト所有=501)をそのまま読み書きできる
#  - --dangerously-skip-permissions が使える(root だと安全のため拒否される)
RUN useradd -m -u 501 -s /bin/bash dev

# 箱内 git の dubious ownership 回避。mount された /work は所有者判定で git に弾かれるため、
# system 設定で全ディレクトリを信頼する(ro マウントされる user の ~/.gitconfig には潰されない)。
# これが無いと claude / hikizan hooks が箱内で叩く git が全部止まる。
RUN git config --system --add safe.directory '*'

# 箱内 git push は ssh 鍵ではなく gh トークンの HTTPS で通す(box 側が insteadOf で書き換える)ため、
# ssh の host key 焼き込みは不要。箱に渡す鍵の到達範囲を「GitHub の push 用途だけ」に絞る狙い。

USER dev
# 初回設定ファイルが無いという警告を抑止(中身は実行時に claude が補完)
RUN printf '{}' > /home/dev/.claude.json
WORKDIR /work
CMD ["bash"]
