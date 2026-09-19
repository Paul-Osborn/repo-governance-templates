#!/bin/sh
# Branch guard: refuse commits on the default branch. POSIX sh (lefthook runs `run:` via Git's
# bundled sh). Kept as a separate LF-only script so Windows CRLF / PowerShell quoting cannot break it.
# git symbolic-ref works on an unborn HEAD (before the first commit); git rev-parse HEAD would not.
branch=$(git symbolic-ref --short -q HEAD || echo HEAD)
if [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
  echo "Refused: commit on $branch. Branch first: git switch -c <type>/<short-desc>"
  exit 1
fi
