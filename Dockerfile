# Apple Container 用「エージェント放牧」サンドボックス
# 箱の中で Claude Code を隔離して走らせるための最小イメージ。
FROM docker.io/library/node:22

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

# GitHub の host key を焼き込む。箱は --rm で毎回 known_hosts が空になるため、素の git push が
# "Host key verification failed" で止まる。build 時に取得し system known_hosts に固定しておく。
RUN ssh-keyscan github.com >> /etc/ssh/ssh_known_hosts 2>/dev/null

USER dev
# 初回設定ファイルが無いという警告を抑止(中身は実行時に claude が補完)
RUN printf '{}' > /home/dev/.claude.json
WORKDIR /work
CMD ["bash"]
