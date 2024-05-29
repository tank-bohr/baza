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

require 'loog'
require 'backtrace'
require_relative 'humans'
require_relative 'urror'

# Pipeline of jobs.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2009-2024 Yegor Bugayenko
# License:: MIT
class Baza::Pipeline
  attr_reader :pgsql

  def initialize(humans, fbs, loog)
    @humans = humans
    @fbs = fbs
    @loog = loog
  end

  def start(pause = 15)
    @thread ||= Thread.new do
      loop do
        job = pop
        sleep pause
        next if job.nil?
        @loog.info("Job ##{job.id} starts: #{job.uri1}")
        Dir.mktmpdir do |dir|
          input = File.join(dir, 'input.fb')
          @fbs.load(job.uri1, input)
          output = File.join(dir, 'output.fb')
          start = Time.now
          stdout = Loog::Buffer.new
          code = run(input, output, stdout)
          uuid = code.zero? ? @fbs.save(output) : nil
          job.finish!(uuid, stdout.to_s, code, ((Time.now - start) * 1000).to_i)
          @loog.info("Job ##{job.id} finished, exit=#{code}!")
        end
      rescue StandardError => e
        @loog.error(Backtrace.new(e))
      end
    end
    @loog.info('Pipeline started')
  end

  def stop
    @thread.terminate
    @loog.info('Pipeline stopped')
  end

  # Is it empty? Nothing to process any more?
  def empty?
    humans.pgsql.exec('SELECT id FROM job WHERE taken IS NULL').empty?
  end

  private

  def pop
    me = "baza #{Baza::VERSION}"
    rows = @humans.pgsql.exec('UPDATE job SET taken = $1 WHERE taken IS NULL RETURNING id', [me])
    return nil if rows.empty?
    @humans.job_by_id(rows[0]['id'].to_i)
  end

  def run(input, output, buf)
    FileUtils.cp(input, output)
    buf.info("Simply copied input FB into output FB (#{File.size(input)} bytes)")
    0
  end
end
