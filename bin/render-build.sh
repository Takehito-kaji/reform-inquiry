#!/usr/bin/env bash
# Render がデプロイのたびに実行する準備の手順
set -o errexit

bundle install
bundle exec rails assets:precompile
bundle exec rails assets:clean
bundle exec rails db:migrate
