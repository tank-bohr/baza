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
require_relative '../../objects/baza'
require_relative '../../objects/baza/factbases'
require_relative '../../objects/baza/humans'
require_relative '../test__helper'

# Test.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2009-2024 Yegor Bugayenko
# License:: MIT
class Baza::GcTest < Minitest::Test
  def test_finds_too_old
    humans = Baza::Humans.new(fake_pgsql)
    humans.gc.ready_to_expire(0) do |j|
      j.expire!(Baza::Factbases.new('', ''))
    end
    assert_equal(0, humans.gc.ready_to_expire(0).to_a.size)
    human = humans.ensure(fake_name)
    token = human.tokens.add(fake_name)
    name = fake_name
    (0..4).each do |i|
      j = token.start(name, fake_name, 1, 0, 'n/a', [])
      j.finish!(fake_name, 'stdout', i, i, 433, 0)
    end
    assert_equal(0, humans.gc.ready_to_expire(1).to_a.size)
    assert_equal(4, humans.gc.ready_to_expire(0).to_a.size)
  end

  def test_finds_stuck
    humans = Baza::Humans.new(fake_pgsql)
    humans.gc.stuck(0) do |j|
      j.expire!(Baza::Factbases.new('', ''))
    end
    human = humans.ensure(fake_name)
    token = human.tokens.add(fake_name)
    job = token.start(fake_name, fake_name, 1, 0, 'n/a', [])
    humans.pgsql.exec("UPDATE job SET taken = 'yes' WHERE id = $1", [job.id])
    assert_equal(1, humans.gc.stuck(0).to_a.size)
  end

  def test_finds_tests
    humans = Baza::Humans.new(fake_pgsql)
    human = humans.ensure(fake_name)
    key = '00000000-0000-0000-0000-000000000000'
    humans.pgsql.exec('INSERT INTO token (human, name, text) VALUES ($1, $2, $3)', [human.id, fake_name, key])
    token = human.tokens.find(key)
    token.start(fake_name, fake_name, 1, 0, 'n/a', [])
    humans.gc.tests(0) do |j|
      j.expire!(Baza::Factbases.new('', ''))
    end
    assert(humans.gc.tests(0).to_a.empty?)
  end
end
