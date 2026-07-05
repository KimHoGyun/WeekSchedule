#!/bin/sh
# 웹앱을 GitHub Pages(gh-pages 브랜치)에 배포한다.
# 사용법: sh tool/deploy_web.sh
set -e
cd "$(dirname "$0")/.."

flutter build web --release --base-href "/WeekSchedule/"
touch build/web/.nojekyll

cd build/web
rm -rf .git
git init -q -b gh-pages
git add -A
git commit -qm "deploy $(date '+%Y-%m-%d %H:%M')"
git push -f https://github.com/KimHoGyun/WeekSchedule.git gh-pages
rm -rf .git

echo "배포 완료: https://kimhogyun.github.io/WeekSchedule/ (반영까지 1~2분)"
