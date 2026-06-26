# Apple Container 用「エージェント放牧」サンドボックス
# 箱の中で Claude Code を隔離して走らせるための最小イメージ。
FROM docker.io/library/node:22

# エージェントCLIを事前インストール(毎回 npm install しないで済む)
# 更新はこのイメージを焼き直す(container build)ことで行う
RUN npm install -g @anthropic-ai/claude-code

# 箱の中では自動アップデートしない(焼き込み式・再現性のため。書込不可で失敗する警告も消える)
ENV DISABLE_AUTOUPDATER=1

# 非rootユーザー。uid をホスト(501)に合わせる理由:
#  - マウントしたファイル(ホスト所有=501)をそのまま読み書きできる
#  - --dangerously-skip-permissions が使える(root だと安全のため拒否される)
RUN useradd -m -u 501 -s /bin/bash dev

USER dev
# 初回設定ファイルが無いという警告を抑止(中身は実行時に claude が補完)
RUN printf '{}' > /home/dev/.claude.json
WORKDIR /work
CMD ["bash"]
