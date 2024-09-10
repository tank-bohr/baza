# frozen_string_literal: true

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

require 'minitest/autorun'
require 'random-port'
require_relative '../test__helper'

# Test.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2009-2024 Yegor Bugayenko
# License:: MIT
class PopTest < Minitest::Test
  def test_runs_script
    loog = fake_loog
    job = fake_job
    s = fake_human.swarms.add(fake_name, "#{fake_name}/#{fake_name}", 'master', '/')
    Dir.mktmpdir do |home|
      %w[aws].each do |f|
        sh = File.join(home, f)
        File.write(sh, "#!/bin/bash\necho $@")
        FileUtils.chmod('+x', sh)
      end
      FileUtils.copy(File.join(__dir__, '../../swarms/pop/entry.sh'), home)
      File.write(
        File.join(home, 'Dockerfile'),
        '
        FROM ruby:3.3
        WORKDIR /r
        RUN apt-get update -y && apt-get install -y jq zip unzip curl
        COPY entry.sh aws .
        RUN chmod a+x aws
        ENV PATH=/r:${PATH}
        ENTRYPOINT ["/bin/bash", "entry.sh"]
        '
      )
      img = 'test-pop'
      bash("docker build #{home} -t #{img}", loog)
      RandomPort::Pool::SINGLETON.acquire do |port|
        fake_front(port, loog) do
          stdout = bash(
            [
              'docker run --add-host host.docker.internal:host-gateway ',
              "-e BAZA_URL -e SWARM_ID -e SWARM_SECRET --rm #{img} 0 ."
            ].join,
            loog,
            'BAZA_URL' => "http://host.docker.internal:#{port}",
            'SWARM_ID' => s.id.to_s,
            'SWARM_SECRET' => s.secret
          )
          [
            'inflating: pack/base.fb',
            'inflating: pack/job.json',
            'adding: base.fb (stored',
            'adding: job.json',
            "aws s3 cp pack.zip s3://swarms.zerocracy.com/baza-j/#{job.id}.zip",
            'aws sqs send-message --queue-url https://sqs.us-east-1.amazonaws.com/019644334823/baza-j'
          ].each { |t| assert(stdout.include?(t), t) }
        ensure
          bash("docker rmi #{img}", loog)
        end
      end
    end
  end
end
