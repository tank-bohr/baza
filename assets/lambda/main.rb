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

require 'aws-sdk-core'
require 'aws-sdk-s3'
require 'aws-sdk-sqs'
require 'backtrace'
require 'elapsed'
require 'English'
require 'iri'
require 'json'
require 'loog'
require 'typhoeus'
require 'archive/zip'

# This is needed because of this: https://github.com/aws/aws-lambda-ruby-runtime-interface-client/issues/14
require 'aws_lambda_ric'
require 'io/console'
require 'stringio'
module AwsLambdaRuntimeInterfaceClient
  class LambdaRunner
    def send_error_response(lambda_invocation, err, exit_code = nil, runtime_loop_active = true)
      error_object = err.to_lambda_response
      @lambda_server.send_error_response(
        request_id: lambda_invocation.request_id,
        error_object: error_object,
        error: err,
        xray_cause: XRayCause.new(error_object).as_json
      )
      @exit_code = exit_code unless exit_code.nil?
      @runtime_loop_active = runtime_loop_active
    end
  end
end

# Download object from AWS S3.
#
# @param [String] key The key in the bucket
# @param [String] file The path of the file to upload
# @param [Loog] loog The logging facility
def get_object(key, file, loog)
  bucket = '{{ bucket }}'
  Aws::S3::Client.new.get_object(
    response_target: file,
    bucket:,
    key:
  )
  loog.info("Loaded S3 object #{key.inspect} from bucket #{bucket.inspect}")
end

# Upload object to AWS S3.
#
# @param [String] key The key in the bucket
# @param [String] file The path of the file to upload
# @param [Loog] loog The logging facility
def put_object(key, file, loog)
  bucket = '{{ bucket }}'
  File.open(file, 'rb') do |f|
    Aws::S3::Client.new.put_object(
      body: f,
      bucket:,
      key:
    )
  end
  loog.info("Saved S3 object #{key.inspect} to bucket #{bucket.inspect}")
end

# Send message to AWS SQS queue "shift", to enable further processing.
#
# @param [Integer] id The ID of the job just processed
# @param [Loog] loog The logging facility
def send_message(id, loog)
  Aws::SQS::Client.new.send_message(
    queue_url: "https://sqs.{{ region }}.amazonaws.com/{{ account }}/baza-shift",
    message_body: "Job ##{id} was processed by {{ name }}",
    message_attributes: {
      'swarm' => {
        string_value: '{{ name }}',
        data_type: 'String'
      },
      'job' => {
        string_value: id.to_s,
        data_type: 'String'
      }
    }
  )
  loog.info("Sent message to SQS about job ##{id}")
end

# Send a report to baza about this particular invocation.
#
# @param [String] stdout Full log of the swarm
# @param [Integer] code Exit code (zero if success, something else otherwise)
# @param [Integer] job The ID of the job just processed (or NIL)
def report(stdout, code, job)
  home = Iri.new('{{ host }}')
    .append('swarms')
    .append('{{ swarm }}'.to_i)
    .append('invocation')
    .add(secret: '{{ secret }}')
    .add(code: code)
  home = home.add(job: job) unless job.nil?
  ret = Typhoeus::Request.put(
    home.to_s,
    connecttimeout: 30,
    timeout: 300,
    body: stdout,
    headers: {
      'User-Agent' => '{{ name }} {{ version }}',
      'Content-Type' => 'text/plain',
      'Content-Length' => stdout.length
    }
  )
  puts "Reported to #{home}: #{ret.code}"
end

# Run one swarm for a particular job, where a ZIP archvie from S3 must be processed.
#
# @param [Integer] id The ID of the job to process
# @param [Hash] rec JSON event from the SQS message
# @param [Loog] loog The logging facility
def with_zip(id, rec, loog)
  Dir.mktmpdir do |home|
    zip = File.join(home, "#{id}.zip")
    key = "{{ name }}/#{id}.zip"
    get_object(key, zip, loog)
    pack = File.join(home, id.to_s)
    Archive::Zip.extract(zip, pack)
    loog.info("Unpacked ZIP (#{File.size(zip)} bytes)")
    File.delete(zip)
    rec_file = File.join(pack, 'event.json')
    File.write(rec_file, JSON.pretty_generate(rec))
    yield pack
    FileUtils.rm_f(rec_file)
    Archive::Zip.archive(zip, File.join(pack, '/.'))
    put_object(key, zip, loog)
    send_message(id, loog)
  end
end

# Run one swarm for a particular job.
#
# @param [Integer] id The ID of the job to process
# @param [String] pack Directory name where the ZIP is unpacked
# @param [Loog] loog The logging facility
def one(id, pack, loog)
  cmd =
    if File.exist?('/swarm/entry.sh')
      "/bin/bash /swarm/entry.sh \"#{id}\" \"#{pack}\" 2>&1"
    elsif File.exist?('/swarm/entry.rb')
      "bundle exec ruby /swarm/entry.rb \"#{id}\" \"#{pack}\" 2>&1"
    else
      "echo 'Cannot figure out how to start the swarm, try creating \"entry.sh\" or \"entry.rb\"'"
    end
  loog.info("+ #{cmd}")
  stdout = `SWARM_SECRET={{ secret }} SWARM_ID={{ swarm }} #{cmd}`
  e = $CHILD_STATUS.exitstatus
  loog.info(stdout)
  loog.warn("FAILURE (#{e})") unless e.zero?
  e
end

# This is the entry point called by aws_lambda_ric when a new SQS message arrives.
#
# @param [Hash] event The JSON event
# @param [LambdaContext] context I don't know what this is for
def go(event:, context:)
  puts "Arrived event: #{event.to_s.inspect}"
  elapsed(intro: 'Job processing finished') do
    event['Records']&.each do |rec|
      loog = Loog::Buffer.new
      loog.info('Version: {{ version }}')
      code = 1
      begin
        job = rec['messageAttributes']['job']['stringValue'].to_i
        loog.info("Event about job ##{job} arrived")
        job = 0 if job.nil?
        if ['baza-pop', 'baza-shift', 'baza-finish'].include?('{{ name }}')
          loog.info("System swarm '{{ name }}' processing")
          Dir.mktmpdir do |pack|
            File.write(File.join(pack, 'event.json'), JSON.pretty_generate(rec))
            code = one(job, pack, loog)
          end
        else
          loog.info("Normal swarm '{{ name }}' processing")
          with_zip(job, rec, loog) do |pack|
            code = one(job, pack, loog)
          end
        end
      rescue StandardError => e
        loog.error(Backtrace.new(e).to_s)
        raise e
      ensure
        report(loog.to_s, code, job)
      end
    end
  end
  'Done!'
end
