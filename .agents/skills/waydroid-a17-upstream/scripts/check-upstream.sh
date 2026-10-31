#!/usr/bin/env bash
# 只读检查各上游相对本项目钉选的变化：waydroid-nvidia、ATV system 镜像、补丁基线、NVIDIA 驱动与 nvrm 版本表、Gerrit。
# 用法：check-upstream.sh [--no-fetch]
set -u
SKILL=$(cd "$(dirname "$0")/.." && pwd -P)
REPO=$(cd "$SKILL/../../.." && pwd -P)
WS=${WAYDROID_A17_WS:-$(dirname "$REPO")}
WN=$WS/nvidia/waydroid-nvidia
NVRM=$WS/nvidia/nvrm
BASES=$REPO/.agents/skills/waydroid-a17-build/references/patch-bases.md
INSTALL=$REPO/aur/waydroid-a17-nvidia-bin/waydroid-a17-nvidia.install
COMPAT=nvidia-prolapse/driver-source/native/src/compat_data.rs
FETCH=1; [ "${1:-}" = --no-fetch ] && FETCH=0

h() { printf '\n== %s\n' "$*"; }
versions() { rg -o '^\("([0-9.]+)", &P[0-9]+\)' -r '$1' | LC_ALL=C sort -u; }
h "waydroid-nvidia（Shiro836）"
[ $FETCH = 1 ] && git -C "$WN" fetch -q origin --tags
gh release list -R Shiro836/waydroid-nvidia --limit 3 | cat
base=$(git -C "$WN" merge-base a17-local origin/main)
echo "分叉点 $(git -C "$WN" log -1 --format='%h %ad %s' --date=short "$base")"
echo "分叉点之后上游的非文档提交（逐条判断是否移植；a17-local 的移植提交用中文标题，git 认不出等价提交）："
git -C "$WN" log --no-merges --reverse --format='  %h %ad %s' --date=short "$base..origin/main" \
  | rg -v -i ' (README|release notes|rc[0-9]+ notes|docs:)' || echo "  （无）"

h "WayDroid-ATV system 镜像"
pin=$(rg -o 'releases/tag/([0-9]{8})' -r '$1' "$INSTALL" | head -1)
latest=$(gh release list -R WayDroid-ATV/waydroid-builds --limit 1 --json tagName,name -q '.[0].tagName+" "+.[0].name')
echo "钉选 $pin；最新 $latest"
[ "${latest%% *}" = "$pin" ] && echo "  一致" || echo "  有新镜像：单独评估（system 镜像换了要重跑整套回归）"

h "补丁基线（$(basename "$BASES")）"
rg '^\| `' "$BASES" | while IFS='|' read -r _ dir _ url branch base _; do
  dir=${dir//[ \`]/}; url=${url// /}; branch=${branch%%（*}; branch=${branch// /}; base=${base//[ \`]/}
  [ "$dir" = waydroid-nvidia ] && continue   # 上面已单独检查
  if [ "$branch" = AOSP ]; then
    # 基线是 manifest 钉选的 AOSP 发布 tag（lineage-24.0 → android-17.0.0_rN），不是 AOSP main
    read -r head branch < <(git ls-remote --tags "$url" 'refs/tags/android-17*' \
      | rg -o '^([0-9a-f]{12})[0-9a-f]*\s+refs/tags/(android-17[^^]*)\^\{\}$' -r '$1 $2' | sort -k2 -V | tail -1)
  else
    head=$(git ls-remote "$url" "refs/heads/$branch" | cut -c1-12)
  fi
  if [ -z "${head:-}" ]; then echo "  $dir：读不到 $url $branch"; continue; fi
  if [ "$head" = "$base" ]; then echo "  $dir：一致（$base）"; continue; fi
  echo "  $dir：基线 $base，上游 $branch 现在是 $head"
  if [[ $url == https://github.com/* ]]; then
    slug=${url#https://github.com/}
    gh api "repos/$slug/compare/$base...$head" \
      -q '"    领先 \(.ahead_by) 个提交", (.commits[] | "    "+.sha[0:7]+" "+.commit.committer.date[0:10]+" "+(.commit.message|split("\n")[0]))'
  fi
done

h "NVIDIA 驱动与 nvrm 版本表"
loaded=$(rg -o 'Kernel Module.*?\s([0-9]+\.[0-9.]+)\s' -r '$1' /proc/driver/nvidia/version 2>/dev/null | head -1)
repo=$(pacman -Si nvidia-open-dkms 2>/dev/null | rg -o '^(Version|版本)\s*:\s*(\S+)' -r '$2' | head -1)
tag=$(git ls-remote --tags https://github.com/NVIDIA/open-gpu-kernel-modules.git | rg -o 'refs/tags/([0-9.]+)$' -r '$1' | sort -V | tail -1)
echo "已加载 ${loaded:-?}；extra 仓库 nvidia-open-dkms ${repo:-?}；NVIDIA 上游最新 tag $tag"
ours=$(versions < "$NVRM/src/compat_data.rs")
for v in $(printf '%s\n' $loaded "${repo%-*}" $tag | sort -u); do
  grep -qx "$v" <<<"$ours" && echo "  $v：nvrm 已支持" || echo "  $v：nvrm 版本表里没有，升级这个驱动前要先适配"
done
theirs=$(git -C "$WN" show "origin/main:$COMPAT" | versions)
missing=$(comm -13 <(echo "$ours") <(echo "$theirs"))
[ -n "$missing" ] && echo "  上游 waydroid-nvidia 有、我们 nvrm 没有的版本：$(echo $missing)" || echo "  nvrm 版本表已覆盖上游全部版本"

h "LineageOS Gerrit 509993（libvulkan R8G8B8 修复）"
curl -s 'https://review.lineageos.org/changes/509993?o=MESSAGES' | tail -n +2 | python3 -c '
import json, sys
d = json.load(sys.stdin)
print("  %s，更新于 %s，%d 条消息" % (d["status"], d["updated"][:10], len(d["messages"])))
for m in d["messages"][-3:]:
    print("   ", m["date"][:10], m.get("author", {}).get("name", "?"), m["message"].splitlines()[0][:100])'
