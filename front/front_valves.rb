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

get '/valves' do
  assemble(:valves, :default, title: '/valves', valves: the_human.valves, offset: Integer((params[:offset] || '0'), 10))
end

post('/valve-add') do
  the_human.valves.enter(params[:name], params[:badge], why: params[:why]) { params[:result] }
  flash(iri.cut('/valves'), "The valve '#{params[:badge]}' has been added for '#{params[:name]}'")
end

get(%r{/valves/([0-9]+)/remove}) do
  id = Integer(params['captures'].first, 10)
  the_human.valves.remove(id)
  flash(iri.cut('/valves'), "The valve ##{id}' just removed")
end
