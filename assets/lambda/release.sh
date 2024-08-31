#!/bin/bash
# MIT License
#
# Copyright (c) 2009-2024 Zerocracy
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

set -ex

PATH=$PATH:$(pwd)

mkdir -p .aws
mv credentials .aws
mv config .aws
aws ecr get-login-password --region "{{ region }}" | docker login --username AWS --password-stdin "{{ repository }}"

checkout() {
  name=$1
  repo=$2
  branch=$3
  mkdir checkouts
  (
    date
    git --version
    uri=git@github.com:${repo}.git
    if [ ! -e ~/.ssh/id_rsa ]; then
      uri=https://github.com/${repo}
    fi
    home=swarms/${name}
    git clone -b "${branch}" --depth=1 --single-branch "${uri}" "${home}"
    git --git-dir "${home}/.git" rev-parse HEAD
  ) 2>&1 | tee "checkouts/${name}"
}

mkdir exits
while IFS= read -r ln; do
  name=$(echo "${ln}" | cut -f1 -d',')
  repo=$(echo "${ln}" | cut -f2 -d',')
  branch=$(echo "${ln}" | cut -f3 -d',')
  echo 0 > "exits/${name}"
  checkout "${name}" "${repo}" "${branch}" || echo "$?" > "exits/${name}"
done < swarms.csv

docker build baza -t baza --platform linux/amd64

docker tag baza "{{ repository }}/{{ image }}"
docker push "{{ repository }}/{{ image }}"

aws lambda update-function-code --function-name baza --image-uri "{{ repository }}/{{ image }}" --publish

