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
require 'factbase'
require_relative '../test__helper'
require_relative '../../objects/baza'
require_relative '../../baza'

class Baza::FrontSwarmsTest < Minitest::Test
  def app
    Sinatra::Application
  end

  def test_read_swarms
    human = fake_job.jobs.human
    fake_login(human.github)
    swarms = human.swarms
    n = fake_name
    repo = "#{fake_name}/#{fake_name}"
    branch = fake_name
    swarm = swarms.add(n, repo, branch)
    get('/swarms')
    assert_status(200)
    get("/swarms/#{swarm.id}/disable")
    assert_status(302)
  end

  def test_swarms_webhook
    human = fake_job.jobs.human
    fake_login(human.github)
    swarms = human.swarms
    n = fake_name
    repo = "#{fake_name}/#{fake_name}"
    branch = fake_name
    swarms.add(n, repo, branch)
    post(
      '/swarms/webhook',
      JSON.pretty_generate({ repository: repo, branch: }),
      'CONTENT_TYPE' => 'application/json'
    )
    assert_status(200)
  end
end
