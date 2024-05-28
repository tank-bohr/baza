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

before '/*' do
  @locals = {
    http_start: Time.now,
    ver: Baza::VERSION,
    github_login_link: settings.glogin.login_uri,
    request_ip: request.ip
  }
  cookies[:auth] = params[:auth] if params[:auth]
  if cookies[:auth]
    begin
      id = GLogin::Cookie::Closed.new(
        cookies[:auth],
        settings.config['github']['encryption_secret']
      ).to_user['id'].to_i
      raise GLogin::Codec::DecodingError unless id.positive?
      @locals[:human] = id
    rescue GLogin::Codec::DecodingError
      cookies.delete(:auth)
    end
  end
end

get '/github-callback' do
  code = params[:code]
  error(400) if code.nil?
  json = settings.glogin.user(code)
  login = json['login']
  json['id'] = settings.humans.ensure(login).id
  cookies[:auth] = GLogin::Cookie::Open.new(
    json, settings.config['github']['encryption_secret']
  ).to_s
  flash(iri.cut('/'), "@#{login} has been logged in")
end

get '/logout' do
  cookies.delete(:auth)
  flash(iri.cut('/'), 'You have been logged out')
end

def the_human
  flash(iri.cut('/'), 'You have to login first') unless @locals[:human]
  settings.humans.get(@locals[:human])
end
