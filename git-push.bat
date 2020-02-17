cd %~dp0
git add -A
git commit -m "update"
git push

bash jekyll-build.sh
git add -A
git commit -m "update" 
git push -f