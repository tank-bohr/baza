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

require 'liquid'
require 'fileutils'

# Function in AWS Lambda.
#
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2009-2024 Yegor Bugayenko
# License:: MIT
class Baza::Lambda
  # Ctor.
  #
  # @param [String] key AWS authentication key (if empty, the object will NOT use AWS S3)
  # @param [String] secret AWS authentication secret
  # @param [String] region AWS region
  # @param [Loog] loog Logging facility
  # @param [Baza:Tbot] tbot Telegram bot
  def initialize(pgsql, key, secret, region, tbot: Baza::Tbot::Fake.new, loog: Loog::NULL)
    @pgsql = pgsql
    @key = key
    @secret = secret
    @region = region
    @tbot = tbot
    @loog = loog
  end

  # Deploy all swarms into AWS lambda.
  def deploy(ecr)
    # check every swarm
    #   if SHA is different in GitHub, add install.sh to package
    # create EC2 instance
    # enter it via SSH
    # upload Dockerfile + all install.sh files
    # run 'docker build'
    # 'docker push' to ECR
    # delete EC2 instance
    # update Lambda function to use new image
  end

  # Package all necessary files for Docker image.
  #
  # @param [String] file Path of the .zip file to create
  def pack(file)
    Dir.mktmpdir do |home|
      dockerfile = ['FROM public.ecr.aws/lambda/ruby:3.2']
      [
        '../../Gemfile',
        '../../Gemfile.lock',
        '../lambda/entry.rb'
      ].each do |f|
        FileUtils.copy(File.join(__dir__, f), File.join(home, File.basename(f)))
        dockerfile << "COPY #{File.basename(f)} ${LAMBDA_TASK_ROOT}/"
      end
      dockerfile += [
        'RUN gem install bundler:2.4.20 && bundle install',
        'WORKDIR /z'
      ]
      @pgsql.exec('SELECT * FROM swarm').each do |row|
        sub = "swarms/#{row['name']}"
        dir = File.join(home, sub)
        `git clone -b #{row['branch']} --depth=1 --single-branch git@github.com:#{row['repository']}.git #{dir}`
        sh = File.join(sub, 'install.sh')
        if File.exist?(File.join(home, sh))
          dockerfile << "COPY #{sh} install"
          dockerfile << "RUN chmod a+x #{sh} && #{sh} && rm #{sh}"
        end
      end
      dockerfile << 'RUN rm -rf /z/swarms'
      dockerfile << 'COPY swarms /z'
      File.write(File.join(home, 'Dockerfile'), dockerfile.join("\n"))
      Baza::Zip.new(file, loog: Loog::VERBOSE).pack(home)
    end
  end
end
