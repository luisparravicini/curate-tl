#!/usr/bin/env ruby -W

require 'json'
require 'English'
require 'date'
require 'set'
require 'uri'
require 'yaml'
require 'optparse'

TWEETS_FNAME = 'tweets.json'.freeze

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

def remove_status(id)
  exec_check_errors("-d 'id=#{id}' /1.1/statuses/destroy/#{id}.json")
end

def user_likes(user)
  json(exec("'/1.1/favorites/list.json?count=200&screen_name=#{user}'"))
end

def unlike(id)
  exec_check_errors("-d 'id=#{id}' /1.1/favorites/destroy.json")
end

def user_timeline(user, max_id)
  args = {
    screen_name: user,
    count: 200,
    # trim_user: true,
    include_rts: true,
    tweet_mode: 'extended'
  }
  args[:max_id] = max_id unless max_id.nil?
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

def load_from_archive(path, prefix)
  data = IO.read(path)

  if data.delete_prefix!("window.YTD.#{prefix}.part0 = ").nil?
    raise 'Unexpected start of archive data'
  end

  JSON.parse(data)
end

def load_likes_from_archive(path)
  path = File.join(path, 'data', 'like.js')
  load_from_archive(path, 'like').map do |datum|
    datum['like']
  end
end

def load_tweets_from_archive(path)
  path = File.join(path, 'data', 'tweet.js')

  {}.tap do |all_tweets|
    load_from_archive(path, 'tweet').each do |datum|
      tweet = datum['tweet']

      id = tweet['id_str']
      all_tweets[id] = tweet
    end
  end
end

def load_tweets(user, resume, archive_path)
  unless archive_path.nil?
    puts 'loading from archive'
    return load_tweets_from_archive(archive_path)
  end

  if resume
    puts 'loading from cache'
    return JSON.parse(IO.read(TWEETS_FNAME))
  end

  {}.tap do |all_tweets|
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
      oldest_tweet = tweets.min_by { |x| x['id'] }
    end

    IO.write(TWEETS_FNAME, JSON.dump(all_tweets))
  end
end

def draw_progress(progress)
  max_progress_size = 40
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

def unlike_all(user, archive_path, deleted_ids, chunk_size, older_days)
  has_data = true
  while has_data
    puts
    print 'fetching likes...'
    likes = if archive_path.nil?
              user_likes(user)
            else
              has_data = false
              print ' (from archive) '
              load_likes_from_archive(archive_path)
            end

    unless older_days.nil?
      likes.delete_if do |tweet|
        # This is the created date for the liked tweet
        # There's no timestamp for the like action so this is the
        # closest in terms of removing likes and leaving only
        # some "new" ones
        created = Date.parse(tweet['created_at'])
        days_old = (Date.today - created).to_i

        days_old > older_days
      end
    end

    puts " (#{likes.size})"

    break if likes.empty?
    return unless confirm('are you sure you want to delete them')

    likes.each_with_index do |tweet, i|
      txt = tweet['text'] || tweet['fullText']
      id = tweet['id_str'] || tweet['tweetId']
      max = likes.size.to_f

      draw_tweet_and_progress(txt, i, max)

      unless deleted_ids.include?(id)
        unlike(id)
        deleted_ids.add(id)
      end

      setup_next_progress_draw

      deleted_ids.save if (i % chunk_size).zero?
    end
    puts
    draw_progress(1)

    deleted_ids.save
  end
end

def confirm(msg)
  puts
  puts '-' * 60
  print "#{msg}? [y/N] "
  answer = $stdin.readline.strip
  puts

  (answer == 'y')
end


def is_rt?(txt)
  txt.start_with?('RT')
end


class DeletedIds
  FNAME = 'deleted_ids.json'.freeze

  def initialize(enabled)
    @data = if enabled && File.exist?(FNAME)
              Set.new(JSON.parse(IO.read(FNAME)))
            else
              Set.new
            end
  end

  def include?(x)
    @data.include?(x)
  end

  def add(x)
    @data << x
  end

  def save
    File.write(FNAME, JSON.dump(@data.to_a))
  end
end

conf = YAML.load(IO.read('conf.yaml'))
user = conf[:username]
puts "user: #{user}"

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"

  opts.on('-r', '--resume', 'Resume deletion using local cache') do
    options[:resume] = true
  end

  opts.on('-R', nil, 'Only delete RTs') do
    options[:rt] = true
  end

  opts.on('-m', nil, 'Only delete tweets starting with a username') do
    options[:mentions] = true
  end

  opts.on('-a', '--archive PATH', 'Read tweets from a Twitter archive for the user') do |path|
    options[:archive] = path
  end

  opts.on('-o', '--older DAYS', Integer, 'Only evaluates tweets older than x days') do |days|
    options[:older_days] = days
  end

  opts.on('-h', '--help', 'Prints this help') do
    puts opts
    exit
  end
end.parse!

resume = options[:resume]
only_mentions = options[:mentions]
only_rt = options[:rt]
older_days = options[:older_days]
chunk_size = 100
archive_path = options[:archive]

from_archive = !options[:archive].nil?
deleted_ids = DeletedIds.new(resume || from_archive)

if confirm('delete likes')
  unlike_all(user, archive_path, deleted_ids, chunk_size, older_days)
end

puts
puts '-' * 60
puts 'fetching tweets to delete'

all_tweets = load_tweets(user, resume, archive_path)

ids_to_remove = []
all_tweets.each do |id, tweet|
  txt = tweet['text'] || tweet['full_text']

  delete = false

  unless only_rt || only_mentions
    delete = true

    hashtags = tweet['entities']['hashtags'].map { |x| x['text'] }
    if !is_rt?(txt) && hashtags.any? { |x| conf[:safe_hashtags].include?(x) }
      delete = false
    end

    if !is_rt?(txt) && conf[:safe_text].any? { |x| txt.downcase.include?(x) }
      delete = false
    end

    if tweet['in_reply_to_screen_name'] == user
      replied_id = tweet['in_reply_to_status_id_str']
      # it might happen that this is a reply to a tweet we haven't
      # got loaded
      if all_tweets.key?(replied_id)
        delete = false
      end
    end
  end

  if only_rt && is_rt?(txt)
    delete = true
  end

  if only_mentions && (txt.start_with?('@') ||
     txt.start_with?('.@'))
    delete = true
  end

  if conf[:safe_prefix].any? { |x| txt.start_with?(x) }
    delete = false
  end

  if conf[:safe_ids].include?(id)
    delete = false
  end

  unless older_days.nil?
    created = Date.parse(tweet['created_at'])
    days_old = (Date.today - created).to_i
    if days_old <= older_days
      delete = false
    end
  end

  next unless delete

  ids_to_remove << {
    id: id,
    txt: txt,
    tweet: tweet
  }
end

$stdout.sync = true

return if ids_to_remove.empty?

ids_to_remove
  .delete_if { |x| deleted_ids.include?(x[:id]) }
  .each_slice(chunk_size) do |ids|
    next if ids.empty?

    puts '-' * 60
    puts

    list_tweets(ids)

    next unless confirm('delete them all')

    puts '-' * 60
    ids.each_with_index do |datum, i|
      txt = datum[:txt]
      id = datum[:id]
      max = ids.size.to_f

      draw_tweet_and_progress(txt, i, max)

      remove_status(id)
      deleted_ids.add(id)

      setup_next_progress_draw
    end
    puts
    draw_progress(1)

    deleted_ids.save

    puts
end
