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

# Swarms of a human.
#
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2009-2024 Yegor Bugayenko
# License:: MIT
class Baza::Swarms
  attr_reader :human

  def initialize(human, tbot: Baza::Tbot::Fake.new)
    @human = human
    @tbot = tbot
  end

  def pgsql
    @human.pgsql
  end

  def get(id)
    raise 'Swarm ID must be an integer' unless id.is_a?(Integer)
    require_relative 'swarm'
    Baza::Swarm.new(self, id, tbot: @tbot)
  end

  def empty?
    pgsql.exec(
      'SELECT id FROM swarm WHERE human = $1',
      [@human.id]
    ).empty?
  end

  def each(offset: 0)
    return to_enum(__method__, offset:) unless block_given?
    rows = pgsql.exec(
      [
        'SELECT * FROM swarm',
        'WHERE human = $1',
        "OFFSET #{offset.to_i}"
      ],
      [@human.id]
    )
    rows.each do |row|
      s = {
        id: row['id'].to_i,
        name: row['name'],
        repository: row['repository'],
        branch: row['branch'],
        dirty: row['dirty'] == 't',
        exit: row['exit']&.to_i,
        stdout: row['stdout'],
        created: Time.parse(row['created'])
      }
      yield s
    end
  end

  # Add new swarm and return its ID.
  #
  # @param [String] name Name of the swarm
  # @param [String] repo Name of repository
  # @param [String] branch Name of branch
  # @return [Baza::Swarm] The added swarm
  def add(name, repo, branch)
    raise Baza::Urror, 'The "name" cannot be empty' if name.empty?
    raise Baza::Urror, "The name #{name.inspect} is not valid" unless name.match?(/^[a-z0-9-]+$/)
    raise Baza::Urror, 'The "repo" cannot be empty' if repo.empty?
    unless repo.match?(%r{^[a-zA-Z][a-zA-Z0-9\-.]*/[a-zA-Z][a-z0-9\-.]*$})
      raise Baza::Urror, "The repo #{repo.inspect} is not valid"
    end
    get(
      pgsql.exec(
        'INSERT INTO swarm (human, name, repository, branch) VALUES ($1, $2, $3, $4) RETURNING id',
        [@human.id, name.downcase, repo, branch]
      )[0]['id'].to_i
    )
  end
end