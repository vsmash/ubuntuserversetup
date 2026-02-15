#!/bin/bash
staging="staging"
# get the current branch name
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
echo "Current branch: $BRANCH_NAME"
# make sure that we are not dirty
if [[ -n $(git status --porcelain) ]]; then
  echo "Working directory is dirty. Please commit or stash your changes before deploying."
    exit 1
fi
      git checkout $staging
      echo -e "\033[0;32mChanged to staging branch: $staging\033[0m"
      git merge develop
      echo -e "\033[0;32mMerged develop into staging\033[0m"
      git push origin $staging
      git checkout $BRANCH_NAME
      echo "Returned to branch: $BRANCH_NAME" 
  # echo in color
  echo -e "\033[0;32mProceeding to deploy to production...\033[0m"

  # change to production branch
  git checkout main
  echo -e "\033[0;32mChanged to production branch: main\033[0m"
  # pull latest changes
  git pull origin main
  echo -e "\033[0;32mPulled latest changes from origin/main\033[0m"
  # merge staging into production
  git merge $staging
  echo -e "\033[0;32mMerged staging into production\033[0m"
  # push production to origin
  git push origin main
  echo -e "\033[0;32mPushed production to origin\033[0m"
  # return to previous branch
  git checkout $BRANCH_NAME
  echo "Deployed to production and returned to branch: $BRANCH_NAME"
