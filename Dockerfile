# Apple Container 用「エージェント放牧」サンドボックス
# 箱の中で Claude Code を隔離して走らせるための最小イメージ。
# ベースは node:24 タグ(現行 LTS。freshness 優先: box update のたびに最新の 24.x とパッチを拾う)。
# 特定バージョンに固定したい重要更新時は node:24@sha256:... の digest pin にする
# (再現性 ⇔ freshness のトレードオフ。通常は freshness を優先)。
FROM docker.io/library/node:24

# ベースイメージ(Debian)の OS パッケージをセキュリティ修正込みで最新化し、
# 常備の便利ツール(jq=JSON整形 / less=ページャ)も入れる。これが無いと node:24
# 公開時点の古い OS パッケージのまま固まり、公開後に出た既知CVEの修正(openssl/
# glibc/git/openssh 等)が取り込まれない。box update(--no-cache 再ビルド)のたびに
# 最新パッチを拾う。最後に apt のインデックスキャッシュを消してイメージを小さく保つ。
RUN apt-get update && apt-get upgrade -y \
 && apt-get install -y --no-install-recommends jq less \
 && rm -rf /var/lib/apt/lists/*

# GitHub CLI(gh)を公式 apt リポジトリから入れる。箱の中のエージェントが
# PR 作成・issue・GitHub API・git push(トークン HTTPS)を自走できるようにするため。
# 公式リポジトリ経由なので box update(--no-cache 再ビルド)のたびに最新版を拾う。
# 署名鍵(trust anchor)は sha256 で pin する: HTTPS 取得した鍵をそのまま信頼(TOFU)せず
# 素性を検証してから apt に渡す(CDN/TLS 侵害時に攻撃者鍵→任意 apt パッケージが build-time root で
# 走る経路を塞ぐ)。GitHub が鍵をローテートするとここで build が落ちる(fail-closed)ので、
# その時は新しい鍵の sha256 に更新する(取得: 箱内で sha256sum <対象ファイル>)。
RUN mkdir -p -m 755 /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "6084d5d7bd8e288441e0e94fc6275570895da18e6751f70f057485dc2d1a811b  /etc/apt/keyrings/githubcli-archive-keyring.gpg" | sha256sum -c - \
 && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y gh \
 && rm -rf /var/lib/apt/lists/*

# 追加 apt パッケージの拡張点。Dockerfile を fork せず box update 時に足せる。
# 例: AGENT_BOX_APT_EXTRA="ripgrep vim tree" box update
ARG APT_EXTRA=""
RUN [ -z "$APT_EXTRA" ] || (apt-get update && apt-get install -y --no-install-recommends $APT_EXTRA && rm -rf /var/lib/apt/lists/*)

# エージェントCLIを事前インストール(毎回 npm install しないで済む)
# 更新はこのイメージを焼き直す(container build)ことで行う。
# claude-code 2.1.x はネイティブbinaryを arch別 optionalDependency で配るが、build 時に
# optional が取りこぼされ "native binary not installed" になることがある。対策として
# linux-arm64 native を明示インストールし、install.cjs を再実行して binary を紐付ける
# (箱は Apple Silicon=arm64 前提)。この回避策は上流が optional 取りこぼしを直せば不要になる
# (その時は arm64 の明示依存と install.cjs 行を外せる)。外し忘れ・破損は末尾の smoke test で検出。
# npm キャッシュは同レイヤに残さない(--no-cache ビルドでもイメージに焼き付くため掃除する)。
RUN npm install -g @anthropic-ai/claude-code @anthropic-ai/claude-code-linux-arm64 @openai/codex \
 && node /usr/local/lib/node_modules/@anthropic-ai/claude-code/install.cjs \
 && npm cache clean --force

# 箱の中では自動アップデートしない(焼き込み式・再現性のため。書込不可で失敗する警告も消える)
ENV DISABLE_AUTOUPDATER=1

# 非rootユーザー。uid をホストに合わせる理由:
#  - マウントしたファイル(ホスト所有)をそのまま読み書きできる
#  - --dangerously-skip-permissions が使える(root だと安全のため拒否される)
# HOST_UID は box update が `--build-arg HOST_UID=$(id -u)` で渡す(未指定なら macOS 既定の 501)。
# macOS のユーザー uid は 501 以降で、node イメージの node(uid 1000)等とは衝突しない前提。
ARG HOST_UID=501
RUN useradd -m -u ${HOST_UID} -s /bin/bash dev

# 箱内 git の dubious ownership 回避。mount された /work は所有者判定で git に弾かれるため、
# system 設定で全ディレクトリを信頼する(ro マウントされる user の ~/.gitconfig には潰されない)。
# これが無いと claude / plugin の hooks が箱内で叩く git が全部止まる。
RUN git config --system --add safe.directory '*'

# 箱内 git push は ssh 鍵ではなく gh トークンの HTTPS で通す(box 側が insteadOf で書き換える)ため、
# ssh の host key 焼き込みは不要。箱に渡す鍵の到達範囲を「GitHub の push 用途だけ」に絞る狙い。

USER dev
# 初回設定ファイルが無いという警告を抑止(中身は実行時に claude が補完)
RUN printf '{}' > /home/dev/.claude.json

# ビルド末尾の smoke test。焼いた CLI が実際に起動するかを build 時に確認する。
# ここが失敗すると container build が失敗し、-t のタグは旧イメージのまま=壊れた箱を掴まない
# (毎回 latest を焼く freshness 優先設計の安全網)。認証不要な範囲(--version/--help)だけ叩く。
RUN echo "[smoke] baked versions:" \
 && claude --version && codex --version && gh --version \
 && claude --help >/dev/null \
 && test -d /usr/local/lib/node_modules/@anthropic-ai/claude-code-linux-arm64 \
 && rm -rf /home/dev/.cache /home/dev/.npm

WORKDIR /work
CMD ["bash"]
