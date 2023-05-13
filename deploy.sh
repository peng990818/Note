# 提交书籍源码
git checkout main
gitbook build
git add .
git commit -m "update"
git push

# 创建部署分支
git branch -d gh-pages
git checkout --orphan gh-pages

# 删除不必要的文件
git rm --cached -r .
git clean -df

# 忽略一些文件
echo "*~" > .gitignore
echo "_book" >> .gitignore
git add .gitignore

# 加入_book下的内容到分支中
cp -r _book/* .
git add .
git commit -m "Publish book"

# 推送分支部署
git push -u origin gh-pages -f

# 切回main分支
git checkout main
