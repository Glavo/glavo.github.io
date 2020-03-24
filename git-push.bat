cd %~dp0
git add -A
git commit -m "update"
git push

bash jekyll-build.sh
cd _site
git add -A
git commit -m "update" 
git push -f