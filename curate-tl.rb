#!/usr/bin/env ruby -W

require 'json'
require 'English'
require 'date'
require 'set'
require 'uri'
require 'yaml'
require 'optparse'


TWEETS_FNAME = 'tweets.json'

def exec(cmd)
  out = `twurl #{cmd}`
  raise "error: #{out}" unless $CHILD_STATUS.success?
  out
end

def json(s)
  JSON.parse(s)
end

def remove_status(id)
  exec("-X POST /1.1/statuses/destroy/#{id}.json")
end

def user_likes(user)
  json(exec("'/1.1/favorites/list.json?count=200&screen_name=#{user}'"))
end

def unlike(id)
  exec("-X POST /1.1/favorites/destroy.json?id=#{id}")
end


def user_timeline(user, max_id)
  args = {
    screen_name: user,
    count: 200,
    # trim_user: true,
    include_rts: true
  }
  unless max_id.nil?
    args[:max_id] = max_id
  end
  args_str = URI.encode_www_form(args)

  json(exec("'/1.1/statuses/user_timeline.json?#{args_str}'"))
end

def list_tweets(tweets)
  tweets.each do |datum|
    created = DateTime.parse(datum[:tweet]['created_at'])
    created_str = created.strftime('%Y-%m-%d')
    puts [created_str, datum[:id], datum[:txt]].join("\t")
  end
end


def load_from_archive(path)
  data = IO.read(path)
  
  unless data.gsub!(%r{^window\.YTD\.tweet\.part0 = }, '')
    raise "Unexpected start of archive data"
  end

  Hash.new.tap do |all_tweets|
    JSON.parse(data).each do |datum|
      tweet = datum['tweet']

      id = tweet['id_str']
      all_tweets[id] = tweet
    end
  end
end

def load_tweets(user, resume, archive_path)
  unless archive_path.nil?
    puts 'loading from archive'
    return load_from_archive(archive_path)
  end

  if resume
    puts 'loading from cache'
    return JSON.parse(IO.read(TWEETS_FNAME))
  end

  Hash.new.tap do |all_tweets|
    last_oldest_tweet = nil
    oldest_tweet = {}

    while last_oldest_tweet != oldest_tweet
      last_oldest_tweet = oldest_tweet

      print "fetching tweets since #{oldest_tweet['created_at']}..."
      tweets = user_timeline(user, oldest_tweet['id_str'])
      print " (#{tweets.size})"
      puts

      tweets.each do |tweet|
        id = tweet['id_str']
        all_tweets[id] = tweet
      end
      oldest_tweet = tweets.sort_by { |x| x['id'] }.first
    end

    IO.write(TWEETS_FNAME, JSON.dump(all_tweets))
  end
end


def draw_progress(progress)
  max_progress_size = 20
  size = (max_progress_size * progress).to_i
  print '['
  print "\u2588" * size
  print "\u2592" * (max_progress_size - size)
  print "] %.0f%%" % (progress * 100)
end

def draw_tweet_and_progress(txt, i, max)
  max_txt = 70
  if txt.size > max_txt
    txt = txt[0..max_txt] + '...'
  end
  puts txt.gsub("\n", ' ')

  progress = i / max
  draw_progress(progress)
end

def setup_next_progress_draw
  ansi_up = "\033[F"
  ansi_clear_line = "\033[2K"
  print ansi_up
  print ansi_clear_line
end

def unlike_all(user)
  while true
    puts
    print 'fetching likes...'
    likes = user_likes(user)
    puts " (#{likes.size})"
    
    break if likes.empty?

    likes.each_with_index do |tweet, i|
      txt = tweet['text']
      id = tweet['id_str']
      max = likes.size.to_f

      draw_tweet_and_progress(txt, i, max)

      unlike(id)

      setup_next_progress_draw
    end
    puts
    draw_progress(1)
  end
end


def confirm(msg)
  puts
  puts '-'*60
  print "#{msg}? [y/N] "
  answer = $stdin.readline.strip
  puts

  (answer == 'y')
end


conf = YAML.load(IO.read('conf.yaml'))
user = conf[:username]
puts "user: #{user}"


options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"

  opts.on("-r", "--resume", "Resume deletion using local cache") do
    options[:resume] = true
  end

  opts.on("-m", nil, "Only delete RTs and tweets starting with a username") do
    options[:rt_and_mentions] = true
  end

  opts.on("-m", nil, "Only delete RTs and tweets starting with a username") do
    options[:rt_and_mentions] = true
  end

  opts.on("-a=PATH", "--archive=PATH", "Read tweets from a Twitter archive for the user") do |path|
    options[:archive] = path
  end

  opts.on("-h", "--help", "Prints this help") do
    puts opts
    exit
  end
end.parse!

resume = options[:resume]
only_rt_and_mentions = options[:rt_and_mentions]
chunk_size = 100


unlike_all(user) if confirm('delete likes')
  

puts
puts '-'*60
puts "fetching tweets to delete"

all_tweets = load_tweets(user, resume, options[:archive])

ids_to_remove = []
all_tweets.each do |id, tweet|
  txt = tweet['text'] || tweet['full_text']

  delete = false

  unless only_rt_and_mentions 
    delete = true

    hashtags = tweet['entities']['hashtags'].map { |x| x['text'] }
    if hashtags.any? { |x| conf[:safe_hashtags].include?(x) }
      delete = false
    end

    if conf[:safe_text].any? { |x| txt.downcase.include?(x) }
      delete = false
    end

    if conf[:safe_ids].include?(id)
      delete = false
    end

    if tweet['in_reply_to_screen_name'] == user
      replied_id = tweet['in_reply_to_status_id_str']
      # it might happen that this is a reply to a tweet we haven't
      # got loaded
      if all_tweets.has_key?(replied_id)
        delete = false
      end
    end
  end

  if txt.start_with?('@') ||
     txt.start_with?('RT') ||
     txt.start_with?('.@')
        delete = true
  end     

  if conf[:safe_prefix].any? { |x| txt.start_with?(x) }
    delete = false
  end

  if delete
    ids_to_remove << {
      id: id,
      txt: txt,
      tweet: tweet
    }
  end
end

DELETED_FNAME = 'deleted_ids.json'
$stdout.sync = true

return if ids_to_remove.empty?
deleted_ids = if resume && File.exist?(DELETED_FNAME)
  Set.new(JSON.parse(IO.read(DELETED_FNAME)))
else
  Set.new
end
ids_to_remove.each_slice(chunk_size) do |ids|
  ids.delete_if { |x| deleted_ids.include?(x[:id]) }
  next if ids.empty?

  puts '-'*60
  puts

  list_tweets(ids)

  next unless confirm('delete them all')

  puts '-'*60
  ids.each_with_index do |datum, i|
    txt = datum[:txt]
    id = datum[:id]
    max = ids.size.to_f

    draw_tweet_and_progress(txt, i, max)

    remove_status(id)
    deleted_ids << id

    setup_next_progress_draw
  end
  puts
  draw_progress(1)

  File.write(DELETED_FNAME, JSON.dump(deleted_ids.to_a))

  puts
end
