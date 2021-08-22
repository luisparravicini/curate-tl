# curate-tl

The script was written to curate my own tweets, it *might* be useful to someone else.

It needs [twurl](https://github.com/twitter/twurl), read it's documentation to install and setup it up. Or follow the [tutorial on Twitter](https://developer.twitter.com/en/docs/tutorials/using-twurl).

After having twurl running, copy `demo-conf.yaml` to `conf.yaml` and edit it with our data and filters.

`curate-tl.rb` does the following:

 * Asks if you want to delete your likes
 * Retrieves all the tweets it can, it stores them in `tweets.json`
 * It lists tweets that match the criteria for deletion in batchs and asks if you want to proceed. After removing them, it continues with the next batch.


 It accepts the following parameters:

 `-r` / `--resume` Reads the tweets from the local cache (`tweets.json`) instead of retrieving them with the api

`-R` Only deletes RTs

`-m` Only deletes tweets that start mentioning a username

`-a PATH` Reads tweets and likes from the [archive downloaded from Twitter](https://help.twitter.com/en/managing-your-account/how-to-download-your-twitter-archive). Sometimes, the api doesn't return all the old tweets, so this is a way to access those old tweets. Use the path where the zip was decompressed.

`-o days` Only evaluate tweets older (in days) than the value specified.

## last tweets

`last_tweet.rb` fetches the list of users the current user (the one you logged in with _twurl_) is following and then list the date of the last tweet/RT made.
Once the list of users is fetched, it's stored in _friends.json_ as a cache, if you want to fetch it again, delete that file.

