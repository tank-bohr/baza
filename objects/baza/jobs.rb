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

require 'veil'

# Jobs of a human.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2009-2024 Yegor Bugayenko
# License:: MIT
class Baza::Jobs
  attr_reader :human

  def initialize(human)
    @human = human
  end

  def pgsql
    @human.pgsql
  end

  def empty?
    pgsql.exec('SELECT job.id FROM job JOIN token ON token.id = job.token WHERE token.human = $1', [@human.id]).empty?
  end

  def start(token, name, uri1, size, errors, agent, meta)
    raise(Baza::Urror, "The name '#{name}' is not valid, make it low-case") unless name.match?(/^[a-z0-9-]+$/)
    raise(Baza::Urror, "The size '#{size}' is not positive") unless size.positive?
    raise(Baza::Urror, 'The agent is empty') if agent.empty?
    raise(Baza::Urror, 'The meta is nil') if meta.nil?
    id =
      pgsql.transaction do |t|
        jid = Integer(
          t.exec(
            'INSERT INTO job (token, name, uri1, size, errors, agent) VALUES ($1, $2, $3, $4, $5, $6) RETURNING id',
            [token, name.downcase, uri1, size, errors, agent]
          )[0]['id'],
          10
        )
        meta.each do |m|
          t.exec('INSERT INTO meta (job, text) VALUES ($1, $2)', [jid, m])
        end
        jid
      end
    get(id)
  end

  def each(name: nil, offset: 0)
    sep = ' -===&62la(o$3s===- '
    sql =
      'SELECT job.id, job.created, job.name, job.uri1, job.expired, job.size, job.errors, job.agent, ' \
      'token.id AS tid, token.name AS token_name, ' \
      'lock.id AS lid, lock.created AS when_locked, lock.owner AS lock_owner, ' \
      'result.id AS rid, result.uri2, result.stdout, result.exit, result.msec, ' \
      'result.size AS rsize, result.errors AS rerrors, ' \
      'ROW_NUMBER() OVER (PARTITION BY job.name ORDER BY job.created DESC) AS row, ' \
      'STRING_AGG(meta.text, $2) AS metas ' \
      'FROM job ' \
      'JOIN token ON token.id = job.token ' \
      'LEFT JOIN lock ON lock.human = token.human AND lock.name = job.name ' \
      'LEFT JOIN result ON result.job = job.id ' \
      'LEFT JOIN meta ON meta.job = job.id ' \
      'WHERE token.human = $1 ' \
      "AND #{name.nil? ? 'job.expired IS NULL' : 'job.name = $3'} " \
      'GROUP BY job.id, result.id, lock.id, token.id ' \
      'ORDER BY created DESC'
    sql = "SELECT t.* FROM (#{sql}) AS t WHERE t.row = 1" if name.nil?
    sql += " OFFSET #{Integer(offset, 10)}"
    args = [@human.id, sep]
    args << name unless name.nil?
    pgsql.exec(sql, args).each do |row|
      yield(Veil.new(
        get(Integer(row['id'], 10)),
        id: Integer(row['id'], 10),
        created: Time.parse(row['created']),
        name: row['name'].downcase,
        uri1: row['uri1'],
        agent: row['agent'],
        size: Integer(row['size'], 10),
        taken: row['taken'],
        errors: Integer(row['errors'], 10),
        metas: (row['metas'] || '').split(sep),
        when_locked: row['when_locked'].nil? ? nil : Time.parse(row['when_locked']),
        lock_owner: row['lock_owner'],
        finished?: !row['rid'].nil?,
        expired?: !row['expired'].nil?,
        token: Veil.new(@human.tokens.get(Integer(row['tid'], 10)), name: row['token_name']),
        result: Veil.new(
          @human.results.get(Integer(row['rid'], 10)),
          id: Integer(row['rid'], 10),
          uri2: row['uri2'],
          size: row['rsize'].nil? ? nil : Integer(row['rsize'], 10),
          errors: row['rerrors'].nil? ? nil : Integer(row['rerrors'], 10),
          msec: Integer(row['msec'], 10),
          exit: Integer(row['exit'], 10),
          empty?: row['uri2'].nil?,
          stdout: row['stdout']
        )
      ))
    end
  end

  def get(id)
    raise('Job ID must be an integer') unless id.is_a?(Integer)
    require_relative('job')
    Baza::Job.new(self, id)
  end

  def name_exists?(name)
    !pgsql.exec(
      'SELECT job.id FROM job ' \
      'JOIN token ON token.id = job.token ' \
      'WHERE token.human = $1 AND job.name = $2 AND expired IS NULL ' \
      'LIMIT 1',
      [@human.id, name.downcase]
    ).empty?
  end

  # There is a job by this name that is running now and now yet finished?
  def busy?(name)
    !pgsql.exec(
      'SELECT job.id FROM job ' \
      'JOIN token ON token.id = job.token ' \
      'LEFT JOIN result ON result.job = job.id ' \
      'WHERE token.human = $1 AND job.name = $2 AND job.expired IS NULL AND result.id IS NULL ' \
      'LIMIT 1',
      [@human.id, name.downcase]
    ).empty?
  end

  def recent(name)
    rows = pgsql.exec(
      'SELECT job.id FROM job ' \
      'JOIN token ON token.id = job.token ' \
      'WHERE token.human = $1 AND job.name = $2 AND expired IS NULL ' \
      'ORDER BY job.created DESC ' \
      'LIMIT 1',
      [@human.id, name.downcase]
    )
    raise(Baza::Urror, "No job by the name '#{name}' found") if rows.empty?
    get(Integer(rows[0]['id'], 10))
  end
end
