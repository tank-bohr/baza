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

require_relative 'job'

# One token.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2009-2024 Yegor Bugayenko
# License:: MIT
class Baza::Token
  attr_reader :id, :tokens

  def initialize(tokens, id)
    @tokens = tokens
    @id = id
  end

  def pgsql
    @tokens.pgsql
  end

  def human
    @tokens.human.humans.get(
      @tokens.pgsql.exec('SELECT human FROM token WHERE id = $1', [@id])[0]['human'].to_i
    )
  end

  def deactivate!
    raise Baza::Urror, 'This token cannot be deactivated' if text == Baza::Tokens::TESTER
    @tokens.pgsql.exec('UPDATE token SET active = false WHERE id = $1', [@id])
  end

  def active?
    rows = @tokens.pgsql.exec('SELECT active FROM token WHERE id = $1', [@id])
    raise Baza::Urror, "Token ##{@id} not found" if rows.empty?
    rows[0]['active'] == 't'
  end

  def start(name, uri1, size, errors, agent, meta, ip)
    raise Baza::Urror, 'The token is inactive' unless active?
    unless human.account.balance.positive? || human.extend(Baza::Human::Roles).tester?
      raise Baza::Urror, 'The balance is negative, you cannot post new jobs'
    end
    @tokens.human.jobs.start(@id, name, uri1, size, errors, agent, meta, ip)
  end

  def created
    rows = @tokens.pgsql.exec('SELECT created FROM token WHERE id = $1', [@id])
    raise Baza::Urror, "Token ##{@id} not found" if rows.empty?
    Time.parse(rows[0]['created'])
  end

  def name
    rows = @tokens.pgsql.exec('SELECT name FROM token WHERE id = $1', [@id])
    raise Baza::Urror, "Token ##{@id} not found" if rows.empty?
    rows[0]['name']
  end

  def text
    rows = @tokens.pgsql.exec('SELECT text FROM token WHERE id = $1', [@id])
    raise Baza::Urror, "Token ##{@id} not found" if rows.empty?
    rows[0]['text']
  end

  def jobs_count
    @tokens.pgsql.exec('SELECT COUNT(job.id) AS c FROM job WHERE token = $1', [@id])[0]['c']
  end

  def to_json(*_args)
    {
      id: @id,
      name:,
      text:,
      created:,
      active: active?
    }
  end
end
