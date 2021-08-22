#!/usr/bin/env ruby -W

require 'json'
require 'English'
require 'date'
require 'set'
require 'uri'
require 'yaml'


def exec(cmd)
  `twurl #{cmd}`.tap do |out|
    raise "error: #{out}" unless $CHILD_STATUS.success?
  end
end

def json(str)
  JSON.parse(str)
end

def exec_check_errors(cmd)
  json(exec(cmd)).tap do |out|
    errors = out['errors']
    raise "error: #{errors}" unless errors.nil?
  end
end

def api_fetch_friends(cursor)
  exec_check_errors("'/1.1/friends/list.json?count=200&cursor=#{cursor}'")
end

def fetch_friends
  friends_path = File.join(__dir__, 'friends.json')
  if File.exist?(friends_path)
    return JSON.parse(IO.read(friends_path))
  end

  friends = []
  cursor = -1
  while true do
    puts "fetching friends [#{friends.size}]"
    result = api_fetch_friends(cursor)
    friends += result['users']
    next_cursor = result['next_cursor']
    break if next_cursor == 0

    cursor = next_cursor
  end

  IO.write(friends_path, JSON.dump(friends))

  friends
end


friends = fetch_friends

puts "#{friends.size} friends"
friends.each do |friend|
  status = friend['status']
  friend['last'] = if status
    DateTime.parse(status['created_at'])
  end
end

min_date = Date.new(1900, 1, 1)
friends
  .sort_by { |x| x['last'] || min_date }
  .reverse
  .each do |friend|
    last_tweet = friend['last']
    puts "#{friend['screen_name']}\t#{last_tweet&.strftime('%F %T')}"
  end
