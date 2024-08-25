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

require 'English'
require 'liquid'
require 'fileutils'
require 'digest/sha1'

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
  def initialize(humans, key, secret, region, tbot: Baza::Tbot::Fake.new, loog: Loog::NULL)
    @humans = humans
    @key = key
    @secret = secret
    @region = region
    @tbot = tbot
    @loog = loog
  end

  # Deploy all swarms into AWS Lambda.
  def deploy
    return unless dirty?
    Dir.mktmpdir do |home|
      zip = File.join(home, 'image.zip')
      pack(zip)
      sha = Digest::SHA1.hexdigest(File.binread(zip))
      break if aws_sha == sha
      build_and_publish(zip)
      done!
    end
  end

  # Build a new Docker image in a new EC2 server and publish it to
  # Lambda function.
  def build_and_publish(zip)
    # create EC2 instance
    # enter it via SSH
    # upload zip
    # run 'docker build'
    # 'docker push' to ECR
    # delete EC2 instance
    # update Lambda function to use new image
  end

  # What is the current SHA of the AWS lambda function?
  #
  # @return [String] The SHA or '' if no lambda function found
  def aws_sha
    ''
  end

  # Package all necessary files for Docker image.
  #
  # @param [String] file Path of the .zip file to create
  def pack(file)
    Dir.mktmpdir do |home|
      [
        '../../Gemfile',
        '../../Gemfile.lock',
        '../../assets/lambda/entry.rb'
      ].each do |f|
        FileUtils.copy(File.join(__dir__, f), File.join(home, File.basename(f)))
      end
      installs = []
      each_swarm do |swarm|
        dir = checkout(swarm)
        next if dir.nil?
        sub = "swarms/#{swarm.name}"
        target = File.join(home, sub)
        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.copy_entry(dir, target)
        installs << install(target, sub)
      end
      dockerfile = Liquid::Template.parse(File.read(File.join(__dir__, '../../assets/lambda/Dockerfile'))).render(
        'installs' => installs.join("\n")
      )
      File.write(File.join(home, 'Dockerfile'), dockerfile)
      @loog.debug("This is the Dockerfile:\n#{dockerfile}")
      Baza::Zip.new(file, loog: @loog).pack(home)
    end
  end

  private

  # Create install commands for Docker, from this directory.
  #
  # @param [String] dir The local directory with swarm content files, e.g. "/tmp/bar/foo-contents"
  # @param [String] sub Subdirectory inside docker image, e.g. "swarms/foo"
  def install(dir, sub)
    gemfile = File.join(dir, 'Gemfile.lock')
    if File.exist?(gemfile)
      "RUN bundle install --gemfile=#{sub}/Gemfile"
    else
      ''
    end
  end

  # Checkout swarm and return the directory where it's located. Also,
  # update its SHA if necessary.
  #
  # @param [Baza::Swarm] swarm The swarm
  # @return [String] Path to location
  def checkout(swarm)
    sub = "swarms/#{swarm.name}"
    dir = File.join('/tmp', sub)
    FileUtils.mkdir_p(File.dirname(dir))
    git = ['set -ex', 'date', 'git --version']
    if File.exist?(dir)
      git += ["cd #{dir}", 'git pull']
    else
      git << "git clone -b #{swarm.branch} --depth=1 --single-branch git@github.com:#{swarm.repository}.git #{dir}"
    end
    git << 'git rev-parse HEAD'
    stdout = `(#{git.join(' && ')}) 2>&1`
    @loog.debug(stdout)
    swarm.stdout!(stdout)
    code = $CHILD_STATUS.exitstatus
    swarm.exit!(code)
    return nil unless code.zero?
    dir
  end

  # Iterate all swarms that need to be deployed.
  def each_swarm
    @humans.pgsql.exec('SELECT * FROM swarm').each do |row|
      yield @humans.find_swarm(row['repository'], row['branch'])
    end
  end

  # Returns TRUE if at least one swarm is "dirty" and because of that
  # the entire pack must be re-deployed.
  def dirty?
    !@humans.pgsql.exec('SELECT id FROM swarm WHERE dirty = true').empty?
  end

  # Mark all swarms as "not dirty any more".
  def done!
    @humans.pgsql.exec('UPDATE swarm SET dirty = f')
  end
end
