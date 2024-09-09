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
set -o pipefail

id=$1
home=$2
cd "${home}"

if [ -z "${S3_BUCKET}" ]; then
  S3_BUCKET=swarms--use1-az4--x-s3
fi

swarm=$(cat event.json | jq -r .messageAttributes.swarm.stringValue)
key="${swarm}/${id}.zip"

aws s3 cp "s3://${bucket}/${key}" pack.zip
aws s3 cp pack.zip "s3://${bucket}/${key}"

aws sqs send-message \
  --queue-url https://sqs.us-east-1.amazonaws.com/019644334823/baza-finish \
  --message-body "Job ${id} finished processing" \
  --message-attributes "job={DataType=String,StringValue='${id}'},swarm={DataType=String,StringValue='${swarm}'}"