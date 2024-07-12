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
require_relative 'test__helper'
require_relative '../baza'

class Baza::AppTest < Minitest::Test
  def app
    Sinatra::Application
  end

  def test_renders_public_pages
    pages = [
      '/version',
      '/robots.txt',
      '/',
      '/svg/logo.svg',
      '/png/logo-white.png',
      '/css/main.css'
    ]
    pages.each do |p|
      get(p)
      assert_status(200)
    end
  end

  def test_renders_css
    get('/css/main.css')
    assert_status(200)
    assert(last_response.body.include?('.logo'))
  end

  def test_renders_private_pages
    pages = [
      '/dash',
      '/tokens',
      '/jobs',
      '/locks',
      '/secrets',
      '/valves',
      '/account'
    ]
    login
    pages.each do |p|
      get(p)
      assert_status(200)
    end
  end

  def test_renders_admin_pages
    pages = [
      '/sql',
      '/gift'
    ]
    login('yegor256')
    pages.each do |p|
      get(p)
      assert_status(200)
    end
  end

  def test_creates_and_deletes_token
    login
    get('/tokens')
    post('/tokens/add', 'name=foo')
    assert_status(302)
    id = last_response.headers['X-Zerocracy-TokenId'].to_i
    assert(id.positive?)
    get("/tokens/#{id}/deactivate")
    assert_status(302)
  end

  def test_valves
    uname = 'tester'
    login(uname)
    get('/valves')
    assert_status(200)
    human = app.humans.ensure(uname)
    human.valves.enter('foo', 'boom', 'why') do
      # nothing
    end
    get('/valves')
    assert_status(200)
  end

  def test_lock_unlock
    login(test_name)
    name = test_name
    owner = test_name
    get("/lock/#{name}?owner=#{owner}")
    assert_status(302)
    get("/unlock/#{name}?owner=#{owner}")
    assert_status(302)
    get("/lock/#{name}?owner=#{test_name}")
    assert_status(302)
    get('/locks')
    assert_status(200)
  end
end
