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

require 'others'
require_relative 'tbot'
require_relative 'human'
require_relative 'urror'
require_relative 'zents'
require_relative 'verified'

# All humans.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2009-2024 Yegor Bugayenko
# License:: MIT
class Baza::Humans
  attr_reader :pgsql

  class TokenNotFound < Baza::Urror; end

  def initialize(pgsql, tbot: Baza::Tbot::Fake.new)
    @pgsql = pgsql
    @tbot = tbot
  end

  def gc
    require_relative 'gc'
    Baza::Gc.new(self)
  end

  def get(id)
    raise 'Human ID must be an integer' unless id.is_a?(Integer)
    Baza::Human.new(self, id, tbot: @tbot)
  end

  def exists?(login)
    raise 'Human login must be a String' unless login.is_a?(String)
    !@pgsql.exec('SELECT id FROM human WHERE github = $1', [login.downcase]).empty?
  end

  def find(login)
    raise 'Human login must be a String' unless login.is_a?(String)
    rows = @pgsql.exec(
      'SELECT id FROM human WHERE github = $1',
      [login.downcase]
    )
    raise Baza::Urror, "Human @#{login} not found" if rows.empty?
    get(rows[0]['id'].to_i)
  end

  # Make sure this human exists (create if it doesn't) and return it.
  def ensure(login)
    raise 'Human login must be a String' unless login.is_a?(String)
    raise 'GitHub login is nil' if login.nil?
    raise 'GitHub login is empty' if login.empty?
    raise "GitHub login too long: \"@#{login}\"" if login.length > 64
    rows = @pgsql.exec(
      'INSERT INTO human (github) VALUES ($1) ON CONFLICT DO NOTHING RETURNING id',
      [login.downcase]
    )
    return find(login) if rows.empty?
    get(rows[0]['id'].to_i)
  end

  # Find a human by the text of his token and returns the token (not the human).
  #
  # @return [Baza::Token] THe token just found
  def his_token(text)
    raise "Token (#{text.inspect}) must be a String" unless text.is_a?(String)
    rows = @pgsql.exec(
      'SELECT id, human FROM token WHERE text = $1',
      [text]
    )
    raise TokenNotFound, "Token #{text} not found" if rows.empty?
    row = rows[0]
    get(row['human'].to_i).tokens.get(row['id'].to_i)
  end

  # Get one job by its ID.
  def job_by_id(id)
    rows = @pgsql.exec(
      'SELECT human FROM job JOIN token ON token.id = job.token WHERE job.id = $1',
      [id]
    )
    raise Baza::Urror, "Job ##{id} not found" if rows.empty?
    get(rows.first['human'].to_i).jobs.get(id)
  end

  # Donate to all accounts that are not funded enough (and eligible for donation).
  def donate(amount: 8, days: 30)
    summary = 'Donation'
    rows = @pgsql.exec(
      [
        'INSERT INTO receipt(human, zents, summary)',
        "SELECT human, #{amount.to_i} AS zents, $2 AS summary FROM",
        '  (SELECT human.id AS human, SUM(a.zents) AS balance FROM human',
        '  LEFT JOIN receipt AS a ON a.human = human.id',
        '  LEFT JOIN receipt AS b ON b.human = human.id',
        "    AND b.created > NOW() - INTERVAL '#{days.to_i} DAYS'",
        "    AND b.summary LIKE CONCAT('#{summary}', '%')",
        '    AND b.zents > 0',
        '  WHERE b.id IS NULL',
        '  GROUP BY human.id) AS x',
        'WHERE x.balance < $1 OR x.balance IS NULL',
        'RETURNING human'
      ],
      [amount, summary]
    )
    rows.each do |row|
      human = get(row['human'].to_i)
      human.notify(
        "🍏 We topped up your account by #{amount.zents}.",
        "Now, the balance is #{human.account.balance.zents}.",
        "We do this automatically every #{days} days, if your account doesn't",
        'have enough funds.'
      )
    end
    rows.count
  end

  # Verify one job.
  def verify_one_job
    rows = @pgsql.exec(
      [
        "UPDATE job SET verified = 'START: #{Time.now.utc.iso8601}' WHERE id = ",
        '(SELECT id FROM job WHERE verified IS NULL LIMIT 1)',
        'RETURNING id'
      ]
    )
    return if rows.empty?
    job = job_by_id(rows.first['id'].to_i)
    verdict = Baza::Verified.new(job).verdict
    job.verify!(verdict)
    yield job, verdict
  end
end
